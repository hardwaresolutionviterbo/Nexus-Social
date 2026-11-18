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
  static const String channelName = 'Notifiche Piazly';
  static const String channelDescription =
      'Messaggi, chat e aggiornamenti di Piazly';

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

  /// Chat da aprire perché l'utente ha toccato una notifica (Fase 4, Blocco 5).
  static final ValueNotifier<String?> openChat = ValueNotifier<String?>(null);

  /// Notifica della campanella toccata (commenti, scambi): si apre il suo annuncio.
  static final ValueNotifier<String?> openNotification = ValueNotifier<String?>(null);

  /// Sale di uno quando arriva un messaggio di chat con l'app aperta: la chat si aggiorna
  /// subito invece di aspettare il controllo periodico.
  static final ValueNotifier<int> chatPings = ValueNotifier<int>(0);

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  /// Canale delle chiamate in arrivo (Blocco 10): suoneria, a tutto schermo.
  static const String callChannelId = 'piazly_chiamate';

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
    FirebaseMessaging.onMessageOpenedApp.listen(_opened);
    try {
      final RemoteMessage? first = await FirebaseMessaging.instance.getInitialMessage();
      if (first != null) _opened(first);
    } catch (_) {
      // Nessuna notifica di avvio.
    }
    // App aperta dalla chiamata a tutto schermo (notifica locale).
    try {
      final NotificationAppLaunchDetails? launch = await _local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) _tapped(launch!.notificationResponse);
    } catch (_) {
      // Nessuna chiamata di avvio.
    }

    await _registerInstallation();
  }

  /// Notifica toccata: se è di una chat, l'app la apre.
  static void _opened(RemoteMessage message) {
    final Object? chat = message.data['chat'];
    if (chat is String && chat.isNotEmpty) openChat.value = chat;
    final Object? notifica = message.data['notifica'];
    if (notifica is String && notifica.isNotEmpty) openNotification.value = notifica;
  }

  /// Tocco sulla chiamata a tutto schermo: si apre la chat, dove la chiamata compare.
  static void _tapped(NotificationResponse? r) {
    final String payload = r?.payload ?? '';
    if (payload.startsWith('chiamata:') && payload.length > 9) openChat.value = payload.substring(9);
  }

  static Future<void> _createChannel() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_nexus'),
        ),
        onDidReceiveNotificationResponse: _tapped,
      );
      await _createCallChannel();
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
    // Messaggio di chat con l'app aperta: niente notifica, la chat si aggiorna da sola.
    if (message.data['tipo'] == 'chat' || message.data['tipo'] == 'call') {
      chatPings.value += 1;
      return;
    }
    final RemoteNotification? notification = message.notification;
    final String title = _clean(notification?.title) ?? 'Piazly';
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
      title: 'Piazly',
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

  static Future<void> _createCallChannel() async {
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            callChannelId,
            'Chiamate in arrivo',
            description: 'Chiamate e videochiamate di Piazly',
            importance: Importance.max,
            playSound: true,
            sound: UriAndroidNotificationSound('content://settings/system/ringtone'),
            audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
            enableVibration: true,
          ),
        );
  }

  /// Numero fisso della notifica di una chiamata (uguale in tutti i processi).
  static int callNotificationId(String conversationId) {
    int h = 0x811c9dc5;
    for (final int c in conversationId.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7fffffff;
    }
    return 700000 + (h % 100000);
  }

  /// Chiamata in arrivo con l'app chiusa: a tutto schermo anche con il telefono bloccato,
  /// con la suoneria che continua finché si risponde o per 45 secondi.
  static Future<void> showIncomingCall({required String conversationId, required String title, required String body}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android || conversationId.isEmpty) return;
    await _local.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_nexus')),
      onDidReceiveNotificationResponse: _tapped,
    );
    await _createCallChannel();
    await _local.show(
      id: callNotificationId(conversationId),
      title: title,
      body: body,
      payload: 'chiamata:$conversationId',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          callChannelId,
          'Chiamate in arrivo',
          channelDescription: 'Chiamate e videochiamate di Piazly',
          importance: Importance.max,
          priority: Priority.max,
          icon: 'ic_stat_nexus',
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: true,
          timeoutAfter: 45000,
          visibility: NotificationVisibility.public,
          audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
          sound: const UriAndroidNotificationSound('content://settings/system/ringtone'),
          // Suona di continuo (FLAG_INSISTENT), come una chiamata.
          additionalFlags: Int32List.fromList(<int>[4]),
        ),
      ),
    );
  }

  /// La chiamata è stata vista nell'app (o è finita): via la notifica a tutto schermo.
  static Future<void> cancelIncomingCall(String conversationId) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _local.cancel(id: callNotificationId(conversationId));
    } catch (_) {
      // Già tolta.
    }
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
  // I messaggi con payload "notification" li mostra il sistema. Le chiamate arrivano solo
  // come dati (Fase 4, Blocco 10): qui si mostra la chiamata a tutto schermo.
  if (message.data['tipo'] != 'call') return;
  try {
    await PushNotifications.showIncomingCall(
      conversationId: '${message.data['chat'] ?? ''}',
      title: '${message.data['titolo'] ?? 'Piazly'}',
      body: '${message.data['testo'] ?? 'Chiamata in arrivo'}',
    );
  } catch (error) {
    debugPrint('NEXUS_PUSH call=failed (${error.runtimeType})');
  }
}
