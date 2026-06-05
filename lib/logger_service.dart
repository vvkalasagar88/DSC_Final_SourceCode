import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:permission_handler/permission_handler.dart';

class LoggerService {

  static File? _logFile;

  /*
   * STORAGE PERMISSION
   */
  // static Future<void> requestPermission() async {
  //
  //   if (Platform.isAndroid) {
  //
  //     await Permission.storage.request();
  //
  //     await Permission.manageExternalStorage.request();
  //   }
  // }

  static Future<void> requestPermission() async {

    if (!Platform.isAndroid) {
      return;
    }

    /*
   * STORAGE (Android 6 - 12)
   */
    if (await Permission.storage.isDenied ||
        await Permission.storage.isRestricted) {

      await Permission.storage.request();
    }

    /*
   * ANDROID 11+ (All files access)
   */
    if (await Permission.manageExternalStorage.isDenied) {

      await Permission.manageExternalStorage.request();
    }

    /*
   * ANDROID 13+ (Media permissions)
   */
    if (await Permission.photos.isDenied) {
      await Permission.photos.request();
    }

    if (await Permission.videos.isDenied) {
      await Permission.videos.request();
    }

    if (await Permission.audio.isDenied) {
      await Permission.audio.request();
    }
  }

  /*
   * GET LOG FILE
   */
  static Future<File> _getLogFile() async {

    if (_logFile != null) {
      return _logFile!;
    }

    /*
   * STORAGE PERMISSION
   */
    await Permission.storage.request();

    await Permission.manageExternalStorage
        .request();

    final dir = Directory(
      '/storage/emulated/0/Download',
    );

    if (!(await dir.exists())) {

      await dir.create(
        recursive: true,
      );
    }

    _logFile = File(
      '${dir.path}/dsc_logs.txt',
    );

    if (!(await _logFile!.exists())) {

      await _logFile!.create(
        recursive: true,
      );
    }

    return _logFile!;
  }
  // static Future<File> _getLogFile() async {
  //
  //   if (_logFile != null) {
  //     return _logFile!;
  //   }
  //
  //   await requestPermission();
  //
  //   final dir = Directory(
  //     '/storage/emulated/0/Download',
  //   );
  //
  //   if (dir == null) {
  //     throw Exception(
  //       'Downloads folder unavailable',
  //     );
  //   }
  //
  //   _logFile = File(
  //     '${dir.path}/dsc_logs.txt',
  //   );
  //
  //   if (!(await _logFile!.exists())) {
  //
  //     await _logFile!.create(
  //       recursive: true,
  //     );
  //   }
  //
  //   return _logFile!;
  // }

  /*
   * WRITE LOG
   */
  static Future<void> write(
      String text,
      ) async {

    try {

      final file =
      await _getLogFile();

      final now = DateTime.now();

      final time =
          "${now.hour.toString().padLeft(2, '0')}:"
          "${now.minute.toString().padLeft(2, '0')}:"
          "${now.second.toString().padLeft(2, '0')}";

      await file.writeAsString(
        '[$time] $text\n',
        mode: FileMode.append,
        flush: true,
      );

    } catch (e) {

      debugPrint(
        'LOGGER ERROR: $e',
      );
    }
  }

  /*
   * CLEAR LOGS
   */
  static Future<void> clearLogs() async {

    try {

      final file =
      await _getLogFile();

      if (await file.exists()) {

        await file.writeAsString(
          '',
          flush: true,
        );
      }

    } catch (e) {

      debugPrint(
        'CLEAR LOG ERROR: $e',
      );
    }
  }

  /*
   * GET PATH
   */
  static Future<String> getLogPath() async {

    final file =
    await _getLogFile();

    return file.path;
  }
}