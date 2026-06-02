import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:app_settings/app_settings.dart';
import '../theme/app_colors.dart';

class RomDetector {
  static Future<String?> getRestrictiveBrand() async {
    if (!Platform.isAndroid) return null;
    final info = await DeviceInfoPlugin().androidInfo;
    final brand = info.manufacturer.toLowerCase();
    
    // These ROMs are known to kill background services
    const restrictive = ['xiaomi', 'redmi', 'oppo', 'vivo', 
                         'huawei', 'honor', 'realme', 'oneplus'];
    
    for (final r in restrictive) {
      if (brand.contains(r)) return info.manufacturer;
    }
    return null;
  }

  /// Show one-time guide for restrictive ROMs
  static Future<void> showGuideIfNeeded(BuildContext context) async {
    final brand = await getRestrictiveBrand();
    if (brand == null) return;
    
    // Show only once using FlutterSecureStorage
    const storage = FlutterSecureStorage();
    final shown = await storage.read(key: 'rom_guide_shown');
    if (shown == 'true') return;
    
    await storage.write(key: 'rom_guide_shown', value: 'true');
    
    if (!context.mounted) return;
    
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSecondary,
        title: const Text('خطوة مهمة',
          style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'عشان وصلة تشتغل في الخلفية على جهازك ($brand)، '
          'محتاج تعمل خطوة واحدة بس:\n\n'
          '١. اضغط "فتح الإعدادات"\n'
          '٢. دور على "استهلاك البطارية" أو "الإدارة"\n'
          '٣. اختار "بدون قيود" لتطبيق وصلة\n\n'
          'ده هيمنع انقطاع نقل الملفات.',
          style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('لاحقاً',
              style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryCyan),
            onPressed: () {
              Navigator.pop(ctx);
              // Open battery settings directly
              AppSettings.openAppSettings(type: AppSettingsType.batteryOptimization);
            },
            child: const Text('فتح الإعدادات',
              style: TextStyle(color: AppColors.bgPrimary)),
          ),
        ],
      ),
    );
  }
}
