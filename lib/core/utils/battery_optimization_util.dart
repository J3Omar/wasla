import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class BatteryOptimizationUtil {
  BatteryOptimizationUtil._();

  /// Returns true if the app is already excluded from battery optimization,
  /// or if the platform is not Android.
  static Future<bool> isOptimizationDisabled() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.ignoreBatteryOptimizations.status;
    return status.isGranted;
  }

  /// Opens the exact settings screen for the user to disable battery optimization.
  static Future<void> requestDisableOptimization() async {
    if (!Platform.isAndroid) return;
    await Permission.ignoreBatteryOptimizations.request();
  }
}
