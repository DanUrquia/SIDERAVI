import 'package:flutter_test/flutter_test.dart';
import 'package:sidera_vi/tracking/crew_signals.dart';
import 'package:sidera_vi/tracking/firebase_presence.dart';
import 'package:sidera_vi/tracking/tracking_geometry.dart';

void main() {
  const waypoint = Offset(-5.17, -2.295);
  Offset east(double meters) => displaceOnMars(waypoint, Offset(meters, 0));

  test('Only accepted movement from outside into 5 m can resolve a rescue', () {
    final arrival = RescueArrival(waypoint, waypoint);
    expect(arrival.moved(waypoint, accepted: true), isFalse);
    expect(arrival.moved(east(1), accepted: true), isFalse);
    expect(arrival.moved(east(5.01), accepted: true), isFalse);
    expect(arrival.moved(east(4.99), accepted: true), isTrue);
  });

  test('Restored and reset positions do not qualify as a rescue arrival', () {
    final arrival = RescueArrival(waypoint, east(9));
    expect(arrival.moved(east(3), accepted: false), isFalse);
    expect(arrival.moved(east(2), accepted: true), isFalse);
    expect(arrival.moved(east(8), accepted: true), isFalse);
    expect(arrival.moved(east(4.9), accepted: true), isTrue);
  });

  test('Crew signal decoding rejects invalid coordinates and roster slots', () {
    final data = decodeCrewSignals({
      'pins': {
        'ARES-01': {
          'marsLat': waypoint.dy,
          'marsLon': waypoint.dx,
          'updated': 1,
        },
        'ARES-02': {'marsLat': 100, 'marsLon': 0, 'updated': 1},
        'other': {'marsLat': 0, 'marsLon': 0, 'updated': 1},
      },
      'sos': {
        'id': 'event',
        'sender': 'ARES-02',
        'marsLat': waypoint.dy,
        'marsLon': waypoint.dx,
        'state': 'resolved',
        'started': 1,
        'finishedBy': 'ARES-01',
      },
    });
    expect(data.pins.keys, ['ARES-01']);
    expect(data.pins['ARES-01']!.mars, waypoint);
    expect(data.sos?.state, SosState.resolved);
    expect(data.sos?.finishedBy, 'ARES-01');
  });
}
