import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/discovery/data/discovery_service.dart';
import '../theme/app_colors.dart';

class FirewallDetector {
  static bool _hasChecked = false;

  static void startCheck(BuildContext context, WidgetRef ref) {
    if (_hasChecked) return;
    if (!Platform.isLinux && !Platform.isWindows) return;
    
    _hasChecked = true;
    
    // Wait 10 seconds before checking
    Timer(const Duration(seconds: 10), () async {
      if (!context.mounted) return;
      
      final discoveryState = ref.read(discoveryServiceProvider);
      
      // If no other devices found
      if (discoveryState.hasValue) {
        final devicesMap = discoveryState.value!;
        final others = devicesMap.values.where((d) => !d.isSelf).toList();
        if (others.isEmpty) {
          if (Platform.isLinux) {
            _checkLinuxFirewall(context);
          } else if (Platform.isWindows) {
            _checkWindowsFirewall(context);
          }
        }
      }
    });
  }

  static void _checkLinuxFirewall(BuildContext context) async {
    // Try binding to mDNS port — if fails, firewall is blocking
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4, 5353);
      socket.close();
      // Port accessible — not a firewall issue
    } catch (e) {
      // Port blocked — show guide
      if (context.mounted) {
        _showLinuxFirewallGuide(context);
      }
    }
  }

  static void _showLinuxFirewallGuide(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSecondary,
        title: const Text('مشكلة في اكتشاف الأجهزة',
          style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'الجدار الناري على جهازك بيمنع وصلة من البحث عن الأجهزة.\n\n'
          'لحل المشكلة:\n'
          '١. افتح Terminal\n'
          '٢. انسخ الأمر ده:\n\n'
          'sudo ufw allow mdns\n\n'
          '٣. اعد تشغيل وصلة',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryCyan),
            onPressed: () {
              Clipboard.setData(const ClipboardData(
                text: 'sudo ufw allow mdns && sudo ufw allow 5353/udp'));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم نسخ الأمر ✓')));
            },
            child: const Text('نسخ الأمر',
              style: TextStyle(color: AppColors.bgPrimary)),
          ),
        ],
      ),
    );
  }

  static void _checkWindowsFirewall(BuildContext context) async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4, 5353);
      socket.close();
    } catch (e) {
      if (context.mounted) {
        _showWindowsFirewallGuide(context);
      }
    }
  }

  static void _showWindowsFirewallGuide(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSecondary,
        title: const Text('مشكلة في اكتشاف الأجهزة',
          style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'الجدار الناري على Windows بيمنع البحث عن الأجهزة.\n\n'
          'اضغط "إصلاح تلقائي" وسيطلب منك إذن المسؤول لحل المشكلة.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء',
              style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryCyan),
            onPressed: () async {
              // Run as admin via PowerShell
              await Process.run('powershell', [
                '-Command',
                'Start-Process powershell -Verb RunAs -ArgumentList '
                '"netsh advfirewall firewall add rule name=WaslaMDNS '
                'protocol=UDP dir=in localport=5353 action=allow"'
              ]);
              if (context.mounted) Navigator.pop(ctx);
            },
            child: const Text('إصلاح تلقائي',
              style: TextStyle(color: AppColors.bgPrimary)),
          ),
        ],
      ),
    );
  }
}
