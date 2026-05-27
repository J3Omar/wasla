import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:disk_space_plus/disk_space_plus.dart';

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

  /// Ensures we don't overwrite existing files. 
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
      throw FileSystemException('Cannot create save directory. Check storage permissions.', saveDir);
    }

    final nameWithoutExt = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    
    int counter = 0;
    String newName = fileName;
    String fullPath = p.join(saveDir, newName);

    while (await File(fullPath).exists()) {
      counter++;
      newName = '$nameWithoutExt ($counter)$ext';
      fullPath = p.join(saveDir, newName);
    }

    return fullPath;
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
      baseDir = await getExternalStorageDirectory();
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
}
