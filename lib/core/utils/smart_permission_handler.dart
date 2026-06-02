import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_colors.dart'; // Ensure AppColors is imported

class SmartPermissionHandler {
  /// Request a permission. If denied → show dialog → open settings automatically.
  static Future<bool> request(
    BuildContext context,
    Permission permission,
    String permissionName, // e.g. "Microphone"
    String reasonText, // e.g. "so you can make voice calls"
  ) async {
    var status = await permission.status;

    if (status.isGranted) return true;

    if (status.isDenied) {
      status = await permission.request();
      if (status.isGranted) return true;
    }

    if (status.isPermanentlyDenied || status.isDenied) {
      if (!context.mounted) return false;
      // Show dialog with auto-redirect
      final shouldOpen = await _showSettingsDialog(
        context,
        permissionName,
        reasonText,
      );
      if (shouldOpen) {
        await openAppSettings(); // opens phone settings directly
        // Wait for user to come back
        await Future.delayed(const Duration(seconds: 2));
        // Re-check
        return await permission.isGranted;
      }
      return false;
    }

    return false;
  }

  static Future<bool> _showSettingsDialog(
    BuildContext context,
    String permissionName,
    String reasonText,
  ) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.bgSecondary,
            title: Text(
              '$permissionName Permission Required',
              style: const TextStyle(color: AppColors.textPrimary),
            ),
            content: Text(
              'Wasla needs access to $permissionName $reasonText.\n\n'
              'Tap "Open Settings" and allow the app.',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Not Now',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryCyan,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Open Settings',
                  style: TextStyle(color: AppColors.bgPrimary),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }
}
