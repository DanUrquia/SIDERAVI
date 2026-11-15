import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

import 'crew_signals.dart';
import 'mission_presence.dart';

/// Firebase client settings supplied by the build, without account credentials.
final class FirebasePresenceConfig {
  FirebasePresenceConfig._(this.database, this.apiKey, this.session);

  final Uri database;
  final String apiKey;
  final String session;

  static final FirebasePresenceConfig? current = _fromBuild();
  static const _identityChannel = MethodChannel('sidera_vi/crew_identity');
  final _credentials = <String, Future<_Credential>>{};
  final _connections = <SessionKey, _FirebaseConnection>{};

  /// Enables sharing on the supported device with complete Firebase settings.
  static FirebasePresenceConfig? _fromBuild() {
    if (!Platform.isIOS) return null;
    const url = String.fromEnvironment('SIDERA_DATABASE_URL');
    const apiKey = String.fromEnvironment('SIDERA_FIREBASE_API_KEY');
    const session = String.fromEnvironment('SIDERA_SESSION_ID');
    final database = Uri.tryParse(url);
    if (database == null ||
        !_trustedDatabase(database) ||
        (database.path.isNotEmpty && database.path != '/') ||
        database.hasQuery ||
        database.hasFragment ||
        apiKey.isEmpty ||
        !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(session)) {
      return null;
    }
    return FirebasePresenceConfig._(database, apiKey, session);
  }

  /// Opens the mission only after proving ownership of its enrolled slot.
  Future<PresenceConnection> connect(SessionKey key) async {
    if (key.session != session ||
        (key.astronaut != 'ARES-01' && key.astronaut != 'ARES-02')) {
      throw const PresenceAccessDenied();
    }
    final pending = _credentials.putIfAbsent(
      key.astronaut,
      () => _deviceCredential(key.astronaut),
    );
    final _Credential credential;
    try {
      credential = await pending;
    } catch (_) {
      if (identical(pending, _credentials[key.astronaut])) {
        _credentials.remove(key.astronaut);
      }
      rethrow;
    }
    final token = await credential.token();
    final http = _client();
    try {
      final member = await _request(
        http,
        'GET',
        _sessionUri(database, key, [
          'deviceMembers',
          '${key.astronaut}.json',
        ], token),
      );
      if (member != credential.uid) throw const PresenceEnrollmentPending();
    } on PresenceAccessDenied {
      // A signed-in device still needs an operator's per-mission assignment.
      throw const PresenceEnrollmentPending();
    } finally {
      http.close(force: true);
    }
    // A quick reentry waits for the outgoing connection's final offline write.
    var previous = _connections[key];
    while (previous != null) {
      await previous.closed;
      if (identical(_connections[key], previous)) _connections.remove(key);
      previous = _connections[key];
    }
    final connection = _FirebaseConnection(this, key, credential.token);
    _connections[key] = connection;
    unawaited(
      connection.closed.then((_) {
        if (identical(_connections[key], connection)) _connections.remove(key);
      }),
    );
    return connection;
  }

  Future<_Credential> _deviceCredential(String slot) async {
    final scope = '${database.host}/$slot';
    final stored = await _identityChannel.invokeMapMethod<String, String>(
      'read',
      scope,
    );
    if (stored != null) {
      return _Credential(
        config: this,
        scope: scope,
        uid: stored['uid']!,
        refresh: stored['refreshToken']!,
      ).._savedRefresh = stored['refreshToken'];
    }
    final http = _client();
    try {
      final response =
          (await _request(
                http,
                'POST',
                Uri.https(
                  'identitytoolkit.googleapis.com',
                  '/v1/accounts:signUp',
                  {'key': apiKey},
                ),
                body: jsonEncode({'returnSecureToken': true}),
              ))
              as Map;
      final credential = _Credential(
        config: this,
        scope: scope,
        uid: response['localId'] as String,
        refresh: response['refreshToken'] as String,
      );
      await credential._storeRefresh();
      credential._setToken(
        response['idToken'] as String,
        response['expiresIn'] as String,
      );
      return credential;
    } finally {
      http.close(force: true);
    }
  }
}

/// Renews short-lived ID tokens from the iOS device-only Keychain credential.
final class _Credential {
  _Credential({
    required this.config,
    required this.scope,
    required this.uid,
    required String refresh,
  }) : _refresh = refresh;

  final FirebasePresenceConfig config;
  final String scope;
  final String uid;
  String? _token;
  String _refresh;
  String? _savedRefresh;
  DateTime? _expires;
  Future<void>? _renewing;

  /// Shares one refresh between simultaneous stream and writer requests.
  Future<String> token() async {
    if (_expires case final expiry? when DateTime.now().isBefore(expiry)) {
      return _token!;
    }
    final refresh = _renewing ??= _renew();
    try {
      await refresh;
    } finally {
      if (identical(refresh, _renewing)) _renewing = null;
    }
    return _token!;
  }

  Future<void> _renew() async {
    final http = _client();
    try {
      final response =
          (await _request(
                http,
                'POST',
                Uri.https('securetoken.googleapis.com', '/v1/token', {
                  'key': config.apiKey,
                }),
                form: true,
                body:
                    'grant_type=refresh_token&refresh_token=${Uri.encodeQueryComponent(_refresh)}',
              ))
              as Map;
      if (response['user_id'] != uid) throw const PresenceAccessDenied();
      _refresh = response['refresh_token'] as String;
      await _storeRefresh();
      _setToken(
        response['id_token'] as String,
        response['expires_in'] as String,
      );
    } finally {
      http.close(force: true);
    }
  }

  Future<void> _storeRefresh() async {
    if (_savedRefresh == _refresh) return;
    await FirebasePresenceConfig._identityChannel.invokeMethod<void>('write', {
      'scope': scope,
      'uid': uid,
      'refreshToken': _refresh,
    });
    _savedRefresh = _refresh;
  }

  void _setToken(String value, String seconds) {
    _expires = DateTime.now().add(
      Duration(seconds: (int.parse(seconds) - 60).clamp(0, 3600)),
    );
    _token = value;
  }
}

/// Uses the documented RTDB Server-Sent Events and HTTP write endpoints.
final class _FirebaseConnection implements CrewSignalConnection {
  _FirebaseConnection(this.config, this.key, this.authToken);

  final FirebasePresenceConfig config;
  final SessionKey key;
  final Future<String> Function() authToken;
  final HttpClient _http = _client();
  final _closed = Completer<void>();
  Future<void> get closed => _closed.future;

  Future<Uri> _uri(List<String> path) async =>
      _sessionUri(config.database, key, path, await authToken());

  @override
  Stream<PresenceSnapshot> get snapshots =>
      _stream('presence.json').map(decodePresence);

  @override
  Stream<CrewSignals> get signalSnapshots =>
      _stream('signals.json').map(decodeCrewSignals);

  Stream<Map<String, Object?>> _stream(String node) async* {
    var uri = await _uri([node]);
    var response = await _streamRequest(uri);
    for (
      var attempt = 0;
      response.statusCode == 307 && attempt < 3;
      attempt++
    ) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null) break;
      final redirect = uri.resolve(location);
      if (!_trustedDatabase(redirect)) break;
      // Firebase can redirect streaming clients to its database shard.
      await response.drain<void>().timeout(_timeout);
      uri = redirect.replace(
        queryParameters: {
          ...redirect.queryParameters,
          'auth': await authToken(),
        },
      );
      response = await _streamRequest(uri);
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const PresenceAccessDenied();
    }
    if (response.statusCode != 200) {
      throw const HttpException('Presence unavailable');
    }

    final tree = <String, Object?>{};
    var event = '';
    final data = StringBuffer();
    final lines = response
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(const Duration(seconds: 90));
    await for (final line in lines) {
      if (line.startsWith('event:')) event = line.substring(6).trim();
      if (line.startsWith('data:')) {
        if (data.isNotEmpty) data.writeln();
        data.write(line.substring(5).trimLeft());
      }
      if (line.isNotEmpty) continue;
      if (event == 'cancel') throw const PresenceAccessDenied();
      if (event == 'auth_revoked') return;
      if ((event == 'put' || event == 'patch') && data.isNotEmpty) {
        final message = jsonDecode(data.toString()) as Map;
        mergePresenceEvent(tree, message, patch: event == 'patch');
        yield Map.of(tree);
      }
      event = '';
      data.clear();
    }
  }

  Future<HttpClientResponse> _streamRequest(Uri uri) async {
    final request = await _http.getUrl(uri).timeout(_timeout);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    return request.close().timeout(_timeout);
  }

  static const _serverTime = {'.sv': 'timestamp'};
  static final _random = Random.secure();

  Map<String, Object> _location(Offset mars) => {
    'marsLon': mars.dx,
    'marsLat': mars.dy,
  };

  Map<String, Object> _pose(AstronautPose pose, bool online) => {
    ..._location(pose.mars),
    if (pose.heading != null) 'relativeHeading': pose.heading!,
    'mode': pose.mode.name,
    'quality': pose.quality.name,
    'online': online,
    'updated': _serverTime,
  };

  @override
  Future<void> publish(AstronautPose pose, {required bool online}) async {
    await _request(
      _http,
      'PUT',
      await _uri(['presence', '${key.astronaut}.json']),
      body: jsonEncode(_pose(pose, online)),
    );
  }

  @override
  Future<void> sendPin(Offset destination) async {
    await _request(
      _http,
      'PUT',
      await _uri(['signals', 'pins', '${key.astronaut}.json']),
      body: jsonEncode({..._location(destination), 'updated': _serverTime}),
    );
  }

  @override
  Future<bool> startSos(Offset mars) => _changeSos((current) {
    if (current?['state'] == SosState.active.name) return null;
    return {
      'id': List.generate(
        16,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
      'sender': key.astronaut,
      ..._location(mars),
      'started': _serverTime,
      'state': SosState.active.name,
    };
  });

  @override
  Future<bool> finishSos(String eventId, SosState state) =>
      _changeSos((current) {
        if (current == null ||
            current['id'] != eventId ||
            current['state'] != SosState.active.name ||
            state == SosState.active) {
          return null;
        }
        return {
          ...current,
          'state': state.name,
          'finishedBy': key.astronaut,
          'finished': _serverTime,
        };
      });

  Future<bool> _changeSos(
    Map<String, Object?>? Function(Map<String, Object?>?) change,
  ) async {
    final uri = await _uri(['signals', 'sos.json']);
    final read = await _http.getUrl(uri).timeout(_timeout)
      ..followRedirects = false
      ..headers.set('X-Firebase-ETag', 'true');
    final response = await read.close().timeout(_timeout);
    final payload = await utf8.decoder.bind(response).join().timeout(_timeout);
    final etag = response.headers.value('etag');
    if (response.statusCode != 200 || etag == null) {
      throw const HttpException('Rescue state unavailable');
    }
    final next = change((jsonDecode(payload) as Map?)?.cast<String, Object?>());
    if (next == null) return false;

    final write = await _http.putUrl(uri).timeout(_timeout)
      ..followRedirects = false
      ..headers.set('if-match', etag)
      ..headers.contentType = ContentType.json;
    write.write(jsonEncode(next));
    final result = await write.close().timeout(_timeout);
    await result.drain<void>().timeout(_timeout);
    if (result.statusCode == 412) return false;
    if (result.statusCode != 200) {
      throw const HttpException('Rescue update unavailable');
    }
    return true;
  }

  @override
  void close() {
    if (_closed.isCompleted) return;
    _http.close(force: true);
    _closed.complete();
  }
}

/// Applies a relative RTDB stream event to the two roster rows.
void mergePresenceEvent(
  Map<String, Object?> tree,
  Map message, {
  required bool patch,
}) {
  final path = (message['path'] as String)
      .split('/')
      .where((e) => e.isNotEmpty)
      .toList();
  final data = message['data'];
  if (patch && data is Map) {
    for (final field in data.entries) {
      final relative = (field.key as String).split('/');
      _put(tree, [...path, ...relative], field.value);
    }
  } else {
    _put(tree, path, data);
  }
}

/// Replaces or removes a value at a relative path from an SSE event.
void _put(Map<dynamic, dynamic> tree, List<String> path, Object? data) {
  if (path.isEmpty) {
    tree.clear();
    if (data is Map) tree.addAll(data);
    return;
  }
  var node = tree;
  for (final key in path.take(path.length - 1)) {
    final value = node[key];
    if (value is! Map) node[key] = <String, Object?>{};
    node = node[key] as Map;
  }
  if (data == null) {
    node.remove(path.last);
  } else {
    node[path.last] = data;
  }
}

/// Decodes valid presence without accepting client-supplied names or Earth data.
PresenceSnapshot decodePresence(Map<String, Object?> tree) {
  final crew = <String, CrewPresence>{};
  for (final id in ['ARES-01', 'ARES-02']) {
    final row = tree[id];
    if (row is! Map) continue;
    final lon = row['marsLon'];
    final lat = row['marsLat'];
    final stamp = row['updated'];
    final online = row['online'];
    final heading = row['relativeHeading'];
    final mode = TrackingMode.values
        .where((value) => value.name == row['mode'])
        .firstOrNull;
    final quality = PositionQuality.values
        .where((value) => value.name == row['quality'])
        .firstOrNull;
    if (lon is! num ||
        !lon.isFinite ||
        lon < -180 ||
        lon >= 180 ||
        lat is! num ||
        !lat.isFinite ||
        lat.abs() > 90 ||
        stamp is! int ||
        stamp < 0 ||
        stamp > 4102444800000 ||
        online is! bool ||
        mode == null ||
        quality == null) {
      continue;
    }
    crew[id] = (
      pose: (
        mars: Offset(lon.toDouble(), lat.toDouble()),
        heading: heading is num && heading.isFinite && heading.abs() <= 180
            ? heading.toDouble()
            : null,
        mode: mode,
        quality: quality,
      ),
      updated: DateTime.fromMillisecondsSinceEpoch(stamp, isUtc: true),
      online: online,
    );
  }
  return crew;
}

const _crewSlots = ['ARES-01', 'ARES-02'];

CrewSignals decodeCrewSignals(Map<String, Object?> tree) {
  final pins = <String, CrewPin>{};
  if (tree['pins'] case final Map rows) {
    for (final slot in _crewSlots) {
      if (rows[slot] case final Map row) {
        final mars = _signalLocation(row);
        final updated = _signalTime(row['updated']);
        if (mars != null && updated != null) {
          pins[slot] = (mars: mars, updated: updated);
        }
      }
    }
  }
  CrewSos? sos;
  if (tree['sos'] case final Map row) {
    final id = row['id'];
    final sender = row['sender'];
    final mars = _signalLocation(row);
    final started = _signalTime(row['started']);
    final state = SosState.values
        .where((state) => state.name == row['state'])
        .firstOrNull;
    final finishedBy = row['finishedBy'];
    if (id is String &&
        id.isNotEmpty &&
        sender is String &&
        _crewSlots.contains(sender) &&
        mars != null &&
        started != null &&
        state != null &&
        (state == SosState.active || _crewSlots.contains(finishedBy))) {
      sos = (
        id: id,
        sender: sender,
        mars: mars,
        started: started,
        state: state,
        finishedBy: finishedBy as String?,
      );
    }
  }
  return (pins: Map.unmodifiable(pins), sos: sos);
}

Offset? _signalLocation(Map row) {
  final lon = row['marsLon'];
  final lat = row['marsLat'];
  if (lon is! num ||
      !lon.isFinite ||
      lon < -180 ||
      lon >= 180 ||
      lat is! num ||
      !lat.isFinite ||
      lat.abs() > 90) {
    return null;
  }
  return Offset(lon.toDouble(), lat.toDouble());
}

DateTime? _signalTime(Object? value) =>
    value is int && value >= 0 && value <= 4102444800000
    ? DateTime.fromMillisecondsSinceEpoch(value, isUtc: true)
    : null;

/// Builds a token-authenticated endpoint scoped to the selected mission session.
Uri _sessionUri(
  Uri database,
  SessionKey key,
  List<String> path,
  String token,
) => database.replace(
  pathSegments: [
    'missions',
    key.mission,
    'sessions',
    path.isEmpty ? '${key.session}.json' : key.session,
    ...path,
  ],
  queryParameters: {'auth': token},
);

/// Restricts database tokens to Firebase database HTTPS hosts.
bool _trustedDatabase(Uri url) =>
    url.scheme == 'https' &&
    url.userInfo.isEmpty &&
    !url.hasPort &&
    RegExp(
      r'^[a-z0-9-]+\.(firebaseio\.com|firebasedatabase\.app)$',
    ).hasMatch(url.host);

const _timeout = Duration(seconds: 10);

HttpClient _client() => HttpClient()..connectionTimeout = _timeout;

/// Performs a bounded Firebase request without logging or forwarding credentials.
Future<Object?> _request(
  HttpClient http,
  String method,
  Uri uri, {
  String? body,
  bool form = false,
}) async {
  final request = await http.openUrl(method, uri).timeout(_timeout);
  request.followRedirects = false;
  if (body != null) {
    request.headers.contentType = form
        ? ContentType('application', 'x-www-form-urlencoded')
        : ContentType.json;
    request.write(body);
  }
  final response = await request.close().timeout(_timeout);
  if (response.statusCode == 401 || response.statusCode == 403) {
    throw const PresenceAccessDenied();
  }
  if (response.statusCode != 200) {
    throw const HttpException('Firebase request unavailable');
  }
  return jsonDecode(await utf8.decoder.bind(response).join().timeout(_timeout));
}
