import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_identity_service.dart';

// ──────────────────────────────────────────────
// CONSTANTS
// ──────────────────────────────────────────────
const String _kChannelId = 'go_medical_high';
const String _kChannelName = 'Notificaciones Go Medical';
const String _kChannelDesc =
    'Alertas en tiempo real de soporte, cotizaciones y pedidos';

/// Primary teal color (0xFF0D9488) encoded as int for Android notification LED / accent.
const int _kNotificationColor = 0xFF0D9488;

// ──────────────────────────────────────────────
// SERVICE
// ──────────────────────────────────────────────

/// Singleton service that manages:
///  1. Creation of the Android notification channel (required for heads-up on Android 8+).
///  2. Requesting POST_NOTIFICATIONS permission at runtime (Android 13+, iOS).
///  3. Subscribing to the Supabase `notifications` table via a reactive Stream.
///  4. Showing a native heads-up / banner alert when a new unread row is detected.
///  5. Keeping [unreadCountNotifier] in sync so the badge in the UI updates instantly.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Observable badge count — consumed by ValueListenableBuilder in the AppBar.
  final ValueNotifier<int> unreadCountNotifier = ValueNotifier<int>(0);
  final StreamController<String?> _notificationTapController =
      StreamController<String?>.broadcast();

  final List<StreamSubscription<List<Map<String, dynamic>>>> _subs = [];
  String? _pendingTapPayload;

  Stream<String?> get notificationTapStream =>
      _notificationTapController.stream;

  String? takePendingTapPayload() {
    final payload = _pendingTapPayload;
    _pendingTapPayload = null;
    return payload;
  }

  /// IDs of unread notifications already known at startup — we skip showing
  /// a banner for these so the user isn't spammed on every app launch.
  final Set<String> _seenIds = <String>{};
  final Map<String, Map<String, dynamic>> _latestRowsById =
      <String, Map<String, dynamic>>{};

  // ────────────────────────────────────────────
  // INIT — call once from main() before runApp
  // ────────────────────────────────────────────

  /// Initialises the plugin, creates the Android channel, and requests
  /// notification permission from the user.
  Future<void> init() async {
    // ── Android channel (must exist BEFORE the first notification) ────────
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _kChannelId,
      _kChannelName,
      description: _kChannelDesc,
      importance: Importance.max, // heads-up on lock screen + banner
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    final AndroidFlutterLocalNotificationsPlugin? androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.createNotificationChannel(channel);

    // ── Plugin initialisation settings ────────────────────────────────────
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings darwinSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    try {
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (_notificationTapController.hasListener) {
            _notificationTapController.add(payload);
          } else {
            _pendingTapPayload = payload;
          }
        },
      );
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp ?? false) {
        _pendingTapPayload = launchDetails?.notificationResponse?.payload;
      }
    } catch (e) {
      debugPrint('[NotificationService] init error: $e');
    }

    // ── Request runtime permission (Android 13+ / iOS) ────────────────────
    await _requestPermission();
  }

  /// Shows a system dialog asking the user to allow notifications.
  /// Safe to call multiple times — Android/iOS only shows the dialog once.
  Future<void> _requestPermission() async {
    try {
      // Android 13+
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await androidPlugin?.requestNotificationsPermission();
      debugPrint('[NotificationService] Android permission granted: $granted');
    } catch (e) {
      debugPrint('[NotificationService] Permission request error: $e');
    }
  }

  // ────────────────────────────────────────────
  // REALTIME STREAM
  // ────────────────────────────────────────────

  /// Starts a Supabase reactive Stream subscription filtered to [userId].
  /// The stream fires immediately with the current snapshot, then on every
  /// INSERT / UPDATE / DELETE on the `notifications` table.
  Future<void> startListening(String userId) async {
    stopListening();

    final ownerIds = await _notificationOwnerIds(userId);

    // Fetch initial count before stream emits (avoids momentary 0 flash)
    await updateUnreadCount(userId);

    final initializedOwners = <String>{};

    try {
      for (final ownerId in ownerIds) {
        final sub = Supabase.instance.client
            .from('notifications')
            .stream(primaryKey: ['id'])
            .eq('user_id', ownerId)
            .listen(
              (List<Map<String, dynamic>> rows) {
                _latestRowsById.removeWhere(
                  (_, row) => row['user_id']?.toString() == ownerId,
                );
                for (final row in rows) {
                  final id = row['id']?.toString();
                  if (id != null && id.isNotEmpty) {
                    _latestRowsById[id] = row;
                  }
                }

                // ── Count unread ──────────────────────────────────────────
                final unread = _latestRowsById.values
                    .where((r) => r['is_read'] == false)
                    .toList();
                unreadCountNotifier.value = unread.length;

                // ── Detect brand-new inserts ──────────────────────────────
                final currentUnreadIds = unread.map((r) => r['id'].toString());

                if (initializedOwners.contains(ownerId)) {
                  // Any id that wasn't in our previous snapshot is a new insert
                  final ownerUnread = rows
                      .where((r) => r['is_read'] == false)
                      .toList();
                  for (final row in ownerUnread) {
                    final id = row['id']?.toString();
                    if (id == null || id.isEmpty) continue;
                    if (!_seenIds.contains(id)) {
                      final title =
                          row['title']?.toString() ?? 'Nueva Notificación';
                      final body = row['body']?.toString() ?? '';
                      showHeadsUp(title, body, payload: id);
                    }
                  }
                }

                _seenIds
                  ..clear()
                  ..addAll(currentUnreadIds);
                initializedOwners.add(ownerId);
              },
              onError: (Object err) {
                debugPrint('[NotificationService] Stream error: $err');
              },
            );
        _subs.add(sub);
      }
    } catch (e) {
      debugPrint('[NotificationService] startListening error: $e');
    }
  }

  /// Cancels the stream subscription and resets internal state.
  void stopListening() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    _seenIds.clear();
    _latestRowsById.clear();
  }

  Future<List<String>> _notificationOwnerIds(String userId) async {
    final ids = <String>{userId};
    try {
      final clientId = await AuthIdentityService.getEffectiveClientId();
      if (clientId != null && clientId.trim().isNotEmpty) {
        ids.add(clientId.trim());
      }
    } catch (e) {
      debugPrint('[NotificationService] client_id lookup skipped: $e');
    }
    return ids.toList(growable: false);
  }

  // ────────────────────────────────────────────
  // BADGE / COUNT
  // ────────────────────────────────────────────

  /// One-shot query to refresh the unread count (used on app resume).
  Future<void> updateUnreadCount(String userId) async {
    try {
      final ownerIds = await _notificationOwnerIds(userId);
      final rows = await Supabase.instance.client
          .from('notifications')
          .select('id')
          .inFilter('user_id', ownerIds)
          .eq('is_read', false);
      unreadCountNotifier.value = (rows as List).length;
    } catch (e) {
      debugPrint('[NotificationService] updateUnreadCount error: $e');
    }
  }

  // ────────────────────────────────────────────
  // SHOW NOTIFICATION
  // ────────────────────────────────────────────

  /// Displays a native heads-up banner (Android) / alert (iOS).
  ///
  /// Uses the pre-created high-importance channel so Android shows the
  /// floating heads-up card even when the app is in the foreground.
  Future<void> showHeadsUp(String title, String body, {String? payload}) async {
    // ignore: use_named_constants
    final tealColor = const Color(0xFF0D9488);
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          _kChannelId,
          _kChannelName,
          channelDescription: _kChannelDesc,
          importance: Importance.max,
          priority: Priority.high,
          color: tealColor,
          showWhen: true,
          playSound: true,
          enableVibration: true,
          ticker: title,
        );

    const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    try {
      await _plugin.show(
        // Use a unique id so concurrent notifications don't overwrite each other
        DateTime.now().microsecondsSinceEpoch % 100000,
        title,
        body,
        details,
        payload: payload,
      );
    } catch (e) {
      debugPrint('[NotificationService] showHeadsUp error: $e');
    }
  }

  // Keep old name for backward compatibility
  Future<void> showNativeNotification(String title, String body) =>
      showHeadsUp(title, body);
}
