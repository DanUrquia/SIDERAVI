import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'mission_presence.dart';

/// Firebase client settings supplied by the build, without account credentials.
final class FirebasePresenceConfig {
  FirebasePresenceConfig._(this.database, this.apiKey, this.session);

  final Uri database;
  final String apiKey;
  final String session;

  /// Enables sharing only for a complete, valid HTTPS Firebase configuration.
  static FirebasePresenceConfig? fromBuild() {
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

  /// Authenticates the crew account and verifies its assigned slot before joining.
  Future<ConnectPresence> signIn(
    SessionKey key,
    String email,
    String password,
  ) async {
    if (key.session != session) throw const PresenceAccessDenied();
    final http = _client();
    try {
      final response =
          (await _request(
                http,
                'POST',
                Uri.https(
                  'identitytoolkit.googleapis.com',
                  '/v1/accounts:signInWithPassword',
                  {'key': apiKey},
                ),
                body: jsonEncode({
                  'email': email,
                  'password': password,
                  'returnSecureToken': true,
                }),
              ))
              as Map;
      final token = response['idToken'] as String;
      final uid = response['localId'] as String;
      final member = await _request(
        http,
        'GET',
        _sessionUri(database, key, ['members', '${key.astronaut}.json'], token),
      );
      if (member != uid) throw const PresenceAccessDenied();
      final credential = _Credential(
        config: this,
        token: token,
        refresh: response['refreshToken'] as String,
        expiresIn: response['expiresIn'] as String,
      );
      return (scope) async {
        if (scope != key) throw const PresenceAccessDenied();
        return _FirebaseConnection(this, scope, credential.token);
      };
    } finally {
      http.close(force: true);
    }
  }
}

/// Holds only the current mission's Firebase tokens and renews before expiration.
final class _Credential {
  _Credential({
    required this.config,
    required String token,
    required String refresh,
    required String expiresIn,
  }) : _token = token,
       _refresh = refresh,
       _expires = _expiry(expiresIn);

  final FirebasePresenceConfig config;
  String _token;
  String _refresh;
  DateTime _expires;
  Future<void>? _renewing;

  /// Shares one refresh between simultaneous stream and writer requests.
  Future<String> token() async {
    if (DateTime.now().isAfter(_expires)) {
      final refresh = _renewing ??= _renew();
      try {
        await refresh;
      } finally {
        if (identical(refresh, _renewing)) _renewing = null;
      }
    }
    return _token;
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
      _token = response['id_token'] as String;
      _refresh = response['refresh_token'] as String;
      _expires = _expiry(response['expires_in'] as String);
    } finally {
      http.close(force: true);
    }
  }

  static DateTime _expiry(String seconds) => DateTime.now().add(
    Duration(seconds: (int.parse(seconds) - 60).clamp(0, 3600)),
  );
}

/// Uses the documented RTDB Server-Sent Events and HTTP write endpoints.
final class _FirebaseConnection implements PresenceConnection {
  _FirebaseConnection(this.config, this.key, this.authToken);

  final FirebasePresenceConfig config;
  final SessionKey key;
  final Future<String> Function() authToken;
  final HttpClient _http = _client();

  Future<Uri> _uri([String? astronaut]) async => _sessionUri(
    config.database,
    key,
    astronaut == null ? ['presence.json'] : ['presence', '$astronaut.json'],
    await authToken(),
  );

  @override
  Stream<PresenceSnapshot> get snapshots async* {
    var uri = await _uri();
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
        yield decodePresence(tree);
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

  @override
  Future<void> publish(AstronautPose pose, {required bool online}) async {
    await _request(
      _http,
      'PUT',
      await _uri(key.astronaut),
      body: jsonEncode({
        'marsLon': pose.mars.dx,
        'marsLat': pose.mars.dy,
        if (pose.heading != null) 'relativeHeading': pose.heading,
        'mode': pose.mode.name,
        'quality': pose.quality.name,
        'online': online,
        'updated': {'.sv': 'timestamp'},
      }),
    );
  }

  @override
  void close() => _http.close(force: true);
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

/// Builds a token-authenticated endpoint scoped to the selected mission session.
Uri _sessionUri(
  Uri database,
  SessionKey key,
  List<String> path,
  String token,
) => database.replace(
  pathSegments: ['missions', key.mission, 'sessions', key.session, ...path],
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
