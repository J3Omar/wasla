import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_background/flutter_background.dart';

class BackgroundServiceManager {
  BackgroundServiceManager._();
  static final instance = BackgroundServiceManager._();
  
  int _activeCount = 0;
  
  Future<void> acquire(String reason) async {
    _activeCount++;
    debugPrint('[BGService] acquire($reason) → count=$_activeCount');
    if (_activeCount == 1) {
      // First acquirer — start the service
      if (!Platform.isAndroid) return;
      try {
        const config = FlutterBackgroundAndroidConfig(
          notificationTitle: 'Wasla',
          notificationText: 'Running in background',
          notificationImportance: AndroidNotificationImportance.normal,
          notificationIcon: AndroidResource(
            name: 'ic_launcher', defType: 'mipmap'),
        );
        await FlutterBackground.initialize(androidConfig: config);
        await FlutterBackground.enableBackgroundExecution();
      } catch (e) {
        debugPrint('[BGService] acquire error: $e');
        _activeCount--;
      }
    }
  }
  
  void release(String reason) {
    if (_activeCount <= 0) return;
    _activeCount--;
    debugPrint('[BGService] release($reason) → count=$_activeCount');
    if (_activeCount == 0) {
      // Last one out — stop the service
      if (!Platform.isAndroid) return;
      try {
        FlutterBackground.disableBackgroundExecution();
      } catch (_) {}
    }
  }
  
  // Force release all — use only on app exit
  void releaseAll() {
    _activeCount = 0;
    if (!Platform.isAndroid) return;
    try {
      FlutterBackground.disableBackgroundExecution();
    } catch (_) {}
  }
}
