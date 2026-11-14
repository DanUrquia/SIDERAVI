import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../sensors/sensor_measurements.dart';

/// The position source retained with each simulated pose.
enum TrackingMode {
  demo('DEMO MOVEMENT'),
  live('LIVE SENSORS');

  const TrackingMode(this.label);
  final String label;
}

/// Location quality reflects public movement decisions, without Earth readings.
enum PositionQuality {
  simulated('SIMULATED POSITION'),
  waiting('AWAITING EARTH FIX'),
  unavailable('EARTH LOCATION UNAVAILABLE'),
  uncertain('POSITION UNCERTAIN'),
  accepted('DISPLACEMENT ACCEPTED'),
  paused('TRACKING PAUSED');

  const PositionQuality(this.label);
  final String label;
}

/// The connection state of the current shared mission.
enum ConnectionStatus {
  offline('OFFLINE'),
  connected('CONNECTED'),
  reconnecting('RECONNECTING');

  const ConnectionStatus(this.label);
  final String label;
}

/// Identifies one isolated shared session and its authorized local roster slot.
typedef SessionKey = ({String mission, String session, String astronaut});

/// A simulated position and relative physical heading, safe to share.
typedef AstronautPose = ({
  Offset mars,
  double? heading,
  TrackingMode mode,
  PositionQuality quality,
});

/// The last known shared state of a crew member.
typedef CrewPresence = ({AstronautPose pose, DateTime updated, bool online});

/// Scope and payload for a foreground presence connection.
typedef PresenceSnapshot = Map<String, CrewPresence>;

/// A backend connection scoped to one authorized mission session.
abstract interface class PresenceConnection {
  /// Streams complete snapshots; a stream error or close triggers reconnect.
  Stream<PresenceSnapshot> get snapshots;

  /// Writes only the authenticated local astronaut's simulated pose.
  Future<void> publish(AstronautPose pose, {required bool online});

  /// Releases the stream and credentials specific to this connection.
  void close();
}

/// Indicates that the authenticated user has no access to this mission slot.
final class PresenceAccessDenied implements Exception {
  const PresenceAccessDenied();
}

/// Opens one connection without reusing a subscription across mission sessions.
typedef ConnectPresence = Future<PresenceConnection> Function(SessionKey key);

/// Throttles pose writes, detects stale teammates and reconnects without replay.
final class MissionPresence extends ChangeNotifier {
  MissionPresence({
    required this.key,
    required this.pose,
    required this.restore,
    this.clock = DateTime.now,
  });

  final SessionKey key;
  final AstronautPose Function() pose;
  final ValueChanged<AstronautPose> restore;
  final DateTime Function() clock;

  static const staleAfter = Duration(seconds: 18);
  static const _heartbeat = Duration(seconds: 6);
  static const _orientationInterval = Duration(milliseconds: 250);

  PresenceSnapshot crew = const {};
  ConnectionStatus status = ConnectionStatus.offline;
  ConnectPresence? _connect;
  PresenceConnection? _connection;
  StreamSubscription<PresenceSnapshot>? _subscription;
  Timer? _tick;
  Timer? _retry;
  DateTime? _sentAt;
  AstronautPose? _lastPose;
  Future<void>? _writing;
  Future<void>? _leaving;
  int _epoch = 0;
  bool _active = false;
  bool accessDenied = false;
  bool _restored = false;
  bool _disposed = false;
  bool _stale = true;
  int _failures = 0;

  /// Starts or resumes the selected provider using a single subscription.
  void open(ConnectPresence connect) {
    if (_active || _disposed) return;
    accessDenied = false;
    _connect = connect;
    _active = true;
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => pulse());
    _begin();
  }

  /// Returns true only for a recently updated, online participant.
  bool isFresh(CrewPresence member) {
    final age = clock().difference(member.updated);
    return status == ConnectionStatus.connected &&
        member.online &&
        age >= const Duration(seconds: -5) &&
        age <= staleAfter;
  }

  /// Responds promptly to accepted movement and refreshes stale UI state.
  void pulse() {
    if (!_active || _disposed) return;
    final stale = !crew.values.any(isFresh);
    if (stale != _stale) {
      _stale = stale;
      notifyListeners();
    }
    final connection = _connection;
    if (status != ConnectionStatus.connected ||
        connection == null ||
        _writing != null) {
      return;
    }
    final current = pose();
    final previous = _lastPose;
    final elapsed = _sentAt == null ? _heartbeat : clock().difference(_sentAt!);
    final positional =
        previous == null ||
        current.mode != previous.mode ||
        current.quality != previous.quality;
    final moved = previous != null && current.mars != previous.mars;
    final heading = current.heading;
    final oldHeading = previous?.heading;
    final turned = heading == null || oldHeading == null
        ? heading != oldHeading
        : signedTurn(heading - oldHeading).abs() >= 2;
    if (!(positional ||
        (moved && current.mode == TrackingMode.live) ||
        elapsed >= _heartbeat ||
        ((moved || turned) && elapsed >= _orientationInterval))) {
      return;
    }
    final epoch = _epoch;
    _lastPose = current;
    _sentAt = clock();
    _writing = _publish(connection, current, epoch);
  }

  /// Serializes writes without blocking the local sensor loop.
  Future<void> _publish(
    PresenceConnection connection,
    AstronautPose value,
    int epoch,
  ) async {
    try {
      await connection.publish(value, online: true);
    } catch (error) {
      if (_current(epoch)) _failed(error);
    } finally {
      if (_current(epoch)) {
        _writing = null;
        scheduleMicrotask(pulse);
      }
    }
  }

  /// Opens a stream and restores a stored pose once after an app restart.
  Future<void> _begin() async {
    final epoch = ++_epoch;
    _setStatus(ConnectionStatus.reconnecting);
    try {
      await _leaving;
      if (!_current(epoch)) return;
      final connection = await _connect!(key);
      if (!_current(epoch)) {
        connection.close();
        return;
      }
      _connection = connection;
      _subscription = connection.snapshots.listen(
        (snapshot) {
          if (!_current(epoch)) return;
          if (!_restored) {
            _restored = true;
            if (snapshot[key.astronaut] case final previous?) {
              restore(previous.pose);
            }
          }
          crew = Map.unmodifiable({
            for (final entry in snapshot.entries)
              if (entry.key != key.astronaut) entry.key: entry.value,
          });
          _failures = 0;
          final changedStatus = status != ConnectionStatus.connected;
          _setStatus(ConnectionStatus.connected);
          _stale = !crew.values.any(isFresh);
          if (!changedStatus) notifyListeners();
          pulse();
        },
        onError: (Object error) {
          if (_current(epoch)) _failed(error);
        },
        onDone: () {
          if (_current(epoch)) _reconnect();
        },
      );
    } catch (error) {
      if (_current(epoch)) _failed(error);
    }
  }

  /// Ends authorization failures and retries transient transport failures.
  void _failed(Object error) {
    if (error is PresenceAccessDenied) {
      accessDenied = true;
      suspend();
    } else {
      _reconnect();
    }
  }

  /// Drops an interrupted connection and retries with capped backoff.
  void _reconnect() {
    _detach();
    _setStatus(ConnectionStatus.reconnecting);
    final seconds = [1, 2, 4, 8, 15][_failures.clamp(0, 4)];
    _failures++;
    _retry = Timer(Duration(seconds: seconds), _begin);
  }

  bool _current(int epoch) => _active && !_disposed && epoch == _epoch;

  /// Ends foreground presence and attempts an immediate offline update.
  void suspend() {
    _active = false;
    _tick?.cancel();
    final oldConnection = _connection;
    final oldWrite = _writing;
    final finalPose = pose();
    _detach(close: false);
    if (oldConnection != null &&
        status == ConnectionStatus.connected &&
        !accessDenied) {
      _leaving = _leave(oldConnection, finalPose, oldWrite);
    } else {
      oldConnection?.close();
    }
    _setStatus(ConnectionStatus.offline);
  }

  /// Keeps an offline update ordered behind any last in-flight live write.
  Future<void> _leave(
    PresenceConnection connection,
    AstronautPose value,
    Future<void>? writing,
  ) async {
    try {
      await writing;
      await connection.publish(value, online: false);
    } catch (_) {
      // The heartbeat expires if the final write cannot reach the backend.
    } finally {
      connection.close();
    }
  }

  void _detach({bool close = true}) {
    _epoch++;
    _retry?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    if (close) _connection?.close();
    _connection = null;
    _lastPose = _sentAt = _writing = null;
  }

  void _setStatus(ConnectionStatus value) {
    if (status == value) return;
    status = value;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    suspend();
    super.dispose();
  }
}
