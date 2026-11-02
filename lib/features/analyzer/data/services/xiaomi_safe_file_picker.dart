import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Safe File Picker & Native Broadcast Split-Screen Video Exporter (v4.0 PRO AI).
class XiaomiSafeFilePicker {
  static const MethodChannel _channel = MethodChannel('com.hawkeye.badminton/file_picker');

  static Future<bool> requestStoragePermissions() async {
    if (!Platform.isAndroid) return true;

    try {
      final videoStatus = await Permission.videos.status;
      if (videoStatus.isGranted) return true;

      if (await Permission.videos.request().isGranted) {
        return true;
      }

      final storageStatus = await Permission.storage.status;
      if (storageStatus.isGranted) return true;

      return await Permission.storage.request().isGranted;
    } catch (e) {
      debugPrint('Permission request warning: $e');
      return false;
    }
  }

  static Future<String?> pickVideo() async {
    try {
      await requestStoragePermissions();

      final String? cachedFilePath = await _channel.invokeMethod<String>('pickVideoSafe');
      if (cachedFilePath != null && File(cachedFilePath).existsSync()) {
        return cachedFilePath;
      }
      return null;
    } on PlatformException catch (e) {
      debugPrint('Safe file picker failed: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('Generic file picker error: $e');
      return null;
    }
  }

  static Future<String?> getCacheDirectory() async {
    try {
      return await _channel.invokeMethod<String>('getCacheDirectory');
    } catch (_) {
      return null;
    }
  }

  /// Renders the 976x576 Broadcast Split-Screen HUD video on-device and exports/downloads it.
  static Future<Map<String, dynamic>?> renderAndExportVideo({
    String? inputPath,
    String mode = 'doubles',
    String playerNames = 'Tú, Cường, Nam, Thành',
    String occludedCorner = 'none',
    double sensitivity = 1.2,
    double speedCalib = 1.0,
    String exportTarget = 'gallery',
    ValueChanged<double>? onProgress,
  }) async {
    try {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onExportProgress' && call.arguments is num) {
          onProgress?.call((call.arguments as num).toDouble());
        }
      });

      final result = await _channel.invokeMapMethod<String, dynamic>(
        'renderAndExportVideo',
        {
          'inputPath': inputPath,
          'mode': mode,
          'playerNames': playerNames,
          'occludedCorner': occludedCorner,
          'sensitivity': sensitivity,
          'speedCalib': speedCalib,
          'exportTarget': exportTarget,
        },
      );
      return result;
    } on PlatformException catch (e) {
      debugPrint('Native renderAndExportVideo failed: ${e.message}');
      return {'status': 'error', 'error': e.message ?? 'Lỗi xuất video'};
    } catch (e) {
      debugPrint('Generic renderAndExportVideo error: $e');
      return {'status': 'error', 'error': e.toString()};
    } finally {
      _channel.setMethodCallHandler(null);
    }
  }

  static Future<Map<String, dynamic>?> exportVideoToGallery(String filePath) async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>(
        'exportVideoToGallery',
        {'filePath': filePath},
      );
    } catch (e) {
      debugPrint('exportVideoToGallery error: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> saveVideoAsDialog(String filePath) async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>(
        'saveVideoAsDialog',
        {'filePath': filePath},
      );
    } catch (e) {
      debugPrint('saveVideoAsDialog error: $e');
      return null;
    }
  }

  static Future<bool> shareVideoFile(String filePath) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'shareVideoFile',
        {'filePath': filePath},
      );
      return res?['status'] == 'shared';
    } catch (e) {
      debugPrint('shareVideoFile error: $e');
      return false;
    }
  }
}
