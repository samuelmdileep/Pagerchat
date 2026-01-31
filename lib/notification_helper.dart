import 'package:flutter/foundation.dart'; // 🔥 Required for kIsWeb check
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationHelper {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    // 🌐 WEB CHECK: If running on web, STOP here.
    // (Web browsers crash if you try to use Android/Linux settings)
    if (kIsWeb) return; 

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // Linux settings (for desktop)
    const linuxSettings = LinuxInitializationSettings(defaultActionName: 'Open notification');

    const settings = InitializationSettings(
      android: androidSettings,
      linux: linuxSettings,
    );

    await _notifications.initialize(settings);
  }

  static Future<void> showNotification({
    required String title,
    required String body,
    required String channelId,
  }) async {
    // 🌐 WEB CHECK: Don't try to show local notification on web
    // (Real web push notifications require a complex Service Worker setup)
    if (kIsWeb) return;

    const androidDetails = AndroidNotificationDetails(
      'pager_chat_channel',
      'Pager Chat Messages',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      DateTime.now().millisecond, 
      title, 
      body, 
      details
    );
  }
}