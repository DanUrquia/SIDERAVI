import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'mission_app.dart';

/// Launches the mission interface in immersive mode.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MissionApp());
}
