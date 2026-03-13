import 'dart:io';

import 'package:belair/models/received_file.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';

class AndroidDownloadsService {
  static const MethodChannel _channel = MethodChannel(
    'belair/android_downloads',
  );

  Future<String?> saveToDownloads(ReceivedFile file) async {
    if (!Platform.isAndroid) {
      return null;
    }

    return _channel.invokeMethod<String>('saveToDownloads', {
      'sourcePath': file.path,
      'displayName': file.name,
      'mimeType': lookupMimeType(file.path) ?? 'application/octet-stream',
    });
  }
}
