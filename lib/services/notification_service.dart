import 'dart:io';

import 'package:belair/models/received_file.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    if (!Platform.isAndroid) {
      return;
    }

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await _plugin.initialize(initializationSettings);

    const channel = AndroidNotificationChannel(
      'received_files',
      'Received Files',
      description: 'Alerts when a file finishes downloading in Belair.',
      importance: Importance.high,
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(channel);
  }

  Future<void> showDownloadComplete(ReceivedFile file) async {
    if (!Platform.isAndroid) {
      return;
    }

    await _plugin.show(
      file.path.hashCode,
      'File received',
      file.name,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'received_files',
          'Received Files',
          channelDescription:
              'Alerts when a file finishes downloading in Belair.',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
