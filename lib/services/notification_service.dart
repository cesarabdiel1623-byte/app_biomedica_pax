import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final ValueNotifier<int> unreadCountNotifier = ValueNotifier<int>(0);
  RealtimeChannel? _realtimeChannel;

  /// Initializes the local notifications plugin and requests permission
  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    try {
      await _localNotifications.initialize(
        initializationSettings,
      );

      // Request notification permissions for Android 13+
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Error initializing local notifications: $e');
    }
  }

  /// Starts listening to real-time notification changes in Supabase
  Future<void> startListening(String userId) async {
    stopListening();

    // Initial fetch of unread count
    await updateUnreadCount(userId);

    try {
      _realtimeChannel = Supabase.instance.client
          .channel('public:notifications')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) {
              // Whenever a notification change (insert, update, delete) happens, update unread count
              updateUnreadCount(userId);

              // If it's an insert event, show a native local notification banner
              if (payload.eventType == PostgresChangeEvent.insert) {
                final newRecord = payload.newRecord;
                final title = newRecord['title'] as String? ?? 'Nueva Notificación';
                final body = newRecord['body'] as String? ?? '';
                showNativeNotification(title, body);
              }
            },
          );
      _realtimeChannel!.subscribe();
    } catch (e) {
      debugPrint('Error subscribing to notifications channel: $e');
    }
  }

  /// Stops listening and removes the Supabase channel
  void stopListening() {
    if (_realtimeChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_realtimeChannel!);
      } catch (_) {}
      _realtimeChannel = null;
    }
  }

  /// Queries Supabase to count the number of unread notifications for the user
  Future<void> updateUnreadCount(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);
      
      unreadCountNotifier.value = response.length;
    } catch (e) {
      debugPrint('Error updating unread count: $e');
    }
  }

  /// Triggers a system-level heads-up native notification banner
  Future<void> showNativeNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'go_medical_notifications_channel',
      'Notificaciones de Go Medical',
      channelDescription: 'Canal para alertas de soporte y cotizaciones',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      playSound: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    try {
      await _localNotifications.show(
        DateTime.now().millisecond,
        title,
        body,
        platformDetails,
      );
    } catch (e) {
      debugPrint('Error showing native notification: $e');
    }
  }
}
