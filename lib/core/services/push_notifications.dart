import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Stato della registrazione FCM mostrato nella diagnostica di debug.
enum PushRegistrationState { idle, registering, registered, failed }

/// Gestisce FCM lato dispositivo: canale Android, permesso notifiche,
/// registrazione tramite Firebase Installation ID e visualizzazione in foreground.
///
/// L'FID non viene mai scritto nei log; l'associazione all'account
/// autenticato è gestita da `PushDeviceRegistry`.
abstract final class PushNotifications {
  static const String channelId = 'nexus_social_default';
  static const String channelName = 'Notifiche VoxLine';
  static const String channelDescription =
      'Messaggi, chat e aggiornamenti di VoxLine';

  static final ValueNotifier<String?> installationId = ValueNotifier<String?>(
    null,
  );
  static final ValueNotifier<String> permission = ValueNotifier<String>(
    'sconosciuto',
  );
  static final ValueNotifier<PushRegistrationState> registration =
      ValueNotifier<PushRegistrationState>(PushRegistrationState.idle);
  static final ValueNotifier<int> foregroundMessages = ValueNotifier<int>(0);
  static final ValueNotifier<String?> lastForegroundTitle =
      ValueNotifier<String?>(null);

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static bool _initialized = false;
  static bool _channelReady = false;

  /// Va registrato prima di `runApp`, come richiede FCM per i messaggi in background.
  static void registerBackgroundHandler() {
    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
  }

  /// Crea il canale, chiede il permesso e registra il dispositivo.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _createChannel();
    await requestPermission();

    _foregroundSubscription ??= FirebaseMessaging.onMessage.listen(
      _showForeground,
    );

    await _registerInstallation();
  }

  static Future<void> _createChannel() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_nexus'),
        ),
      );
      final AndroidFlutterLocalNotificationsPlugin? android = _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDescription,
          importance: Importance.high,
          playSound: true,
        ),
      );
      _channelReady = true;
    } catch (error) {
      debugPrint('NEXUS_PUSH channel=failed (${error.runtimeType})');
    }
  }

  /// Su Android 13+ questa chiamata mostra la richiesta di POST_NOTIFICATIONS.
  static Future<String> requestPermission() async {
    try {
      final NotificationSettings settings = await FirebaseMessaging.instance
          .requestPermission(alert: true, badge: true, sound: true);
      final String status =
          settings.authorizationStatus == AuthorizationStatus.authorized
          ? 'granted'
          : settings.authorizationStatus.name;
      permission.value = status;
      debugPrint(
        'NEXUS_PUSH channel=${_channelReady ? 'ready' : 'failed'} '
        'permission=$status',
      );
      return status;
    } catch (error) {
      permission.value = 'errore';
      debugPrint(
        'NEXUS_PUSH channel=${_channelReady ? 'ready' : 'failed'} '
        'permission=failed (${error.runtimeType})',
      );
      return 'errore';
    }
  }

  static Future<void> _registerInstallation() async {
    final FirebaseMessaging messaging = FirebaseMessaging.instance;
    final Completer<String> registered = Completer<String>();
    StreamSubscription<String>? subscription;

    registration.value = PushRegistrationState.registering;
    try {
      await messaging.setAutoInitEnabled(true);

      // firebase_messaging 17 usa la Firebase Installation ID: register() avvia
      // la registrazione e onRegistered restituisce il FID.
      subscription = messaging.onRegistered.listen((String fid) {
        if (!registered.isCompleted) registered.complete(fid);
      });

      // La registrazione FIS può fallire in modo transitorio su rete o
      // emulatore: riprova con un backoff più lungo prima di dichiarare
      // l'errore. Il timeout resta entro l'attesa del job runtime.
      const int maxAttempts = 5;
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          await messaging.register();
          final String fid = await registered.future.timeout(
            const Duration(seconds: 20),
          );
          installationId.value = fid;
          registration.value = PushRegistrationState.registered;
          // Nessun identificativo nel log: solo lo stato.
          debugPrint('NEXUS_FCM registered=true');
          return;
        } on TimeoutException {
          if (attempt == maxAttempts) {
            registration.value = PushRegistrationState.failed;
            debugPrint('NEXUS_FCM error=timeout');
            return;
          }
        } catch (error) {
          if (attempt == maxAttempts) {
            registration.value = PushRegistrationState.failed;
            // Solo il codice Firebase, mai FID o credenziali.
            final String code = error is FirebaseException
                ? error.code
                : error.runtimeType.toString();
            debugPrint('NEXUS_FCM error=$code');
            final String detail = _errorDetail(error);
            if (detail.isNotEmpty) {
              debugPrint('NEXUS_FCM detail=$detail');
            }
            return;
          }
        }

        final int delaySeconds = switch (attempt) {
          1 => 5,
          2 => 10,
          3 => 20,
          _ => 30,
        };
        await Future<void>.delayed(Duration(seconds: delaySeconds));
      }
    } finally {
      await subscription?.cancel();
    }
  }

  /// In foreground FCM non mostra la notifica da solo: la pubblichiamo noi
  /// sullo stesso canale usato dai messaggi in background.
  static Future<void> _showForeground(RemoteMessage message) async {
    final RemoteNotification? notification = message.notification;
    final String title = _clean(notification?.title) ?? 'VoxLine';
    final String body =
        _clean(notification?.body) ?? 'Hai ricevuto un nuovo messaggio.';

    foregroundMessages.value += 1;
    lastForegroundTitle.value = title;
    debugPrint('NEXUS_PUSH foreground=received');

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await _local.show(
        id: _notificationId(message),
        title: title,
        body: body,
        notificationDetails: _details,
      );
    } catch (error) {
      debugPrint('NEXUS_PUSH display=failed (${error.runtimeType})');
    }
  }

  static String? _clean(String? value) {
    final String? trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static int _notificationId(RemoteMessage message) {
    final String? id = message.messageId;
    if (id == null || id.isEmpty) {
      return DateTime.now().millisecondsSinceEpoch.remainder(1 << 31);
    }
    return id.hashCode & 0x7fffffff;
  }

  /// Notifica locale usata solo dalla diagnostica per verificare canale e icona.
  static Future<void> showLocalTest() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _local.show(
      id: 9001,
      title: 'VoxLine',
      body: 'Notifica locale di prova: canale e visualizzazione configurati.',
      notificationDetails: _details,
    );
    debugPrint('NEXUS_PUSH local_test=shown');
  }

  /// Messaggio utile alla diagnosi, senza identificativi o token lunghi.
  static String _errorDetail(Object error) {
    if (error is! FirebaseException) return '';
    final String text = (error.message ?? '').trim();
    final String redacted = text.replaceAll(
      RegExp(r'[A-Za-z0-9_-]{20,}'),
      '<redacted>',
    );
    return redacted.length <= 120 ? redacted : '${redacted.substring(0, 120)}…';
  }

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_nexus',
    ),
  );
}

@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  // I messaggi con payload "notification" vengono mostrati dal sistema usando
  // il canale predefinito configurato nel manifest. Qui resteranno disponibili
  // i messaggi data-only per la Fase 4.
}
