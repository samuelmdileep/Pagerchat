import 'package:flutter/foundation.dart'; // Required for kIsWeb check
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationHelper {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    // 🌐 WEB CHECK: If running on web, STOP here.
    if (kIsWeb) return; 

    // 🤖 Android Settings
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // 🐧 Linux Settings
    const linuxSettings = LinuxInitializationSettings(defaultActionName: 'Open notification');

    // ⚙️ Combine Settings
    const settings = InitializationSettings(
      android: androidSettings,
      linux: linuxSettings,
    );

    // 🔥 FIX 1: Use named parameter 'settings' (We fixed this earlier)
    await _notifications.initialize(
      settings: settings, 
      onDidReceiveNotificationResponse: (details) {
        if (kDebugMode) {
          print("Notification tapped: ${details.payload}");
        }
      },
    );
  }

  static Future<void> showNotification({
    required String title,
    required String body,
    required String channelId,
  }) async {
    if (kIsWeb) return;

    const androidDetails = AndroidNotificationDetails(
      'pager_chat_channel',
      'Pager Chat Messages',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );

    const details = NotificationDetails(android: androidDetails);

    // 🔥 FIX 2: Version 18+ requires NAMED parameters for everything now
    await _notifications.show(
      id: DateTime.now().millisecond, // Named 'id'
      title: title,                   // Named 'title'
      body: body,                     // Named 'body'
      notificationDetails: details,   // Named 'notificationDetails'
    );
  }
}