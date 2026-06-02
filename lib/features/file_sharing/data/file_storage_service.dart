import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import '../../../core/utils/smart_permission_handler.dart';

class FileStorageService {
  FileStorageService._();
  static final FileStorageService instance = FileStorageService._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const String _kSavePathKey = 'file_save_path';

  /// Reads the saved path from storage, or returns the platform default if empty.
  Future<String> getSavePath() async {
    final savedPath = await _storage.read(key: _kSavePathKey);
    if (savedPath != null && savedPath.isNotEmpty) {
      final dir = Directory(savedPath);
      if (await dir.exists()) {
        return savedPath;
      }
    }
    return _getDefaultPath();
  }

  /// Saves the chosen path to storage.
  Future<void> setSavePath(String path) async {
    await _storage.write(key: _kSavePathKey, value: path);
  }

  /// Checks if there is enough free disk space for the incoming file (plus 50MB buffer).
  Future<bool> hasEnoughSpace(int fileSizeBytes) async {
    try {
      final freeSpaceInMB = await DiskSpacePlus().getFreeDiskSpace;
      if (freeSpaceInMB == null) return true; // Fallback if unable to check

      // Convert to bytes
      final freeSpaceBytes = freeSpaceInMB * 1024 * 1024;

      // Require at least the file size + 50MB buffer
      return freeSpaceBytes > (fileSizeBytes + (50 * 1024 * 1024));
    } catch (e) {
      // If plugin fails (e.g. unsupported platform), default to allowing transfer
      return true;
    }
  }

  /// Ensures we don't overwrite existing files and sanitizes the filename.
  /// e.g. "report.pdf" -> "report (1).pdf" -> "report (2).pdf"
  Future<String> resolveDestinationPath(String fileName) async {
    final saveDir = await getSavePath();
    final dir = Directory(saveDir);
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (e) {
      // If we cannot create the directory, likely a permission issue
      throw FileSystemException(
        'Cannot create save directory. Check storage permissions.',
        saveDir,
      );
    }

    final sanitized = _sanitizeFileName(fileName);

    // Safely extract name and extension for the collision loop
    final lastDotIndex = sanitized.lastIndexOf('.');
    final nameWithoutExt = lastDotIndex <= 0
        ? sanitized
        : sanitized.substring(0, lastDotIndex);
    final ext = lastDotIndex <= 0 ? '' : sanitized.substring(lastDotIndex);

    int counter = 0;
    String newName = sanitized;
    String fullPath = p.join(saveDir, newName);

    while (await File(fullPath).exists()) {
      counter++;
      newName = '$nameWithoutExt ($counter)$ext';
      fullPath = p.join(saveDir, newName);
    }

    return fullPath;
  }

  /// Sanitizes filenames to be safe across all operating systems.
  String _sanitizeFileName(String fileName) {
    // 1. Replace illegal characters and control characters with '_'
    // Illegal: \ / : * ? " < > | and ASCII 0-31
    String sanitized = fileName.replaceAll(
      RegExp(r'[\\/:*?"<>|\x00-\x1F]'),
      '_',
    );

    // 2. Collapse multiple spaces into one, trim leading/trailing spaces
    sanitized = sanitized.replaceAll(RegExp(r'\s+'), ' ').trim();

    // 3. Extract name and extension safely
    // If no dot or dot is first char (e.g. ".hidden"), treat as no extension
    String nameWithoutExt;
    String ext;
    final lastDotIndex = sanitized.lastIndexOf('.');
    if (lastDotIndex <= 0) {
      nameWithoutExt = sanitized;
      ext = '';
    } else {
      nameWithoutExt = sanitized.substring(0, lastDotIndex);
      ext = sanitized.substring(lastDotIndex);
    }

    // 4. If after sanitizing the name becomes empty, default to "wasla_file"
    if (nameWithoutExt.isEmpty) {
      nameWithoutExt = 'wasla_file';
    }

    // 5. Max filename length: 200 characters (truncate name, keep extension)
    const maxLength = 200;
    if (nameWithoutExt.length + ext.length > maxLength) {
      final allowedNameLength = maxLength - ext.length;
      if (allowedNameLength > 0) {
        nameWithoutExt = nameWithoutExt.substring(0, allowedNameLength);
      } else {
        // Fallback if the extension itself is strangely longer than 200 chars
        nameWithoutExt = '';
        ext = ext.substring(0, maxLength);
      }
    }

    return '$nameWithoutExt$ext';
  }

  /// Returns a temporary path for the file during the transfer.
  String getTempDestinationPath(String finalPath) {
    return '$finalPath.wasla_tmp';
  }

  /// Renames the temporary file to its final destination.
  Future<void> commitTempFile(String tempPath, String finalPath) async {
    final tempFile = File(tempPath);
    if (await tempFile.exists()) {
      await tempFile.rename(finalPath);
    }
  }

  /// Gets the default platform-specific path for Wasla downloads.
  Future<String> _getDefaultPath() async {
    Directory? baseDir;

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 30) {
        // Android 11+ Scoped Storage: use public Downloads folder
        baseDir = await getDownloadsDirectory();
      } else {
        // Android 10 and below
        baseDir = await getExternalStorageDirectory();
      }
      baseDir ??= await getApplicationDocumentsDirectory();
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      baseDir = await getDownloadsDirectory();
      baseDir ??= await getApplicationDocumentsDirectory();
    } else {
      // iOS / other
      baseDir = await getApplicationDocumentsDirectory();
    }

    final waslaDir = Directory(p.join(baseDir.path, 'Wasla'));
    if (!await waslaDir.exists()) {
      await waslaDir.create(recursive: true);
    }

    return waslaDir.path;
  }

  /// Requests the necessary storage permissions based on Android API level.
  Future<bool> requestStoragePermission(BuildContext context) async {
    if (!Platform.isAndroid) return true;

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    if (androidInfo.version.sdkInt >= 33) {
      // Android 13+ (API 33+) granular media permissions
      if (!context.mounted) return false;
      final photos = await SmartPermissionHandler.request(
        context,
        Permission.photos,
        'Photos',
        'to save incoming files',
      );
      if (!photos) return false;

      if (!context.mounted) return false;
      final videos = await SmartPermissionHandler.request(
        context,
        Permission.videos,
        'Videos',
        'to save incoming files',
      );
      if (!videos) return false;

      if (!context.mounted) return false;
      final audio = await SmartPermissionHandler.request(
        context,
        Permission.audio,
        'Audio',
        'to save incoming files',
      );
      return audio;
    } else {
      // Android 12 and below
      if (!context.mounted) return false;
      return await SmartPermissionHandler.request(
        context,
        Permission.storage,
        'Storage',
        'to save incoming files',
      );
    }
  }
}
