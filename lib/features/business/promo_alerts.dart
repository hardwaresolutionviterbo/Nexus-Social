import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/widgets/piazly_ui.dart';
import 'business_repository.dart';
import 'promotion_models.dart';

/// Avvisi delle promozioni vicine (Fase 6, Blocco 4), solo per chi li accende.
///
/// Tutto avviene sul telefono: la posizione non va al server più di quanto già fa la Mappa
/// (la richiesta delle promozioni intorno), e non si salva da nessuna parte. Il controllo
/// avviene con Piazly aperta o appena riaperta (non in sottofondo), al massimo 3 avvisi al giorno
/// e mai due volte per la stessa promozione.
class PromoAlertState {
  const PromoAlertState({
    this.enabled = false,
    this.radiusM = 1000,
    this.seen = const <String>{},
    this.day = '',
    this.sentToday = 0,
  });

  static const List<int> radiusOptions = <int>[500, 1000, 3000];
  static const int maxPerDay = 3;

  final bool enabled;
  final int radiusM;
  final Set<String> seen;
  final String day;
  final int sentToday;

  PromoAlertState copyWith({bool? enabled, int? radiusM, Set<String>? seen, String? day, int? sentToday}) =>
      PromoAlertState(
        enabled: enabled ?? this.enabled,
        radiusM: radiusM ?? this.radiusM,
        seen: seen ?? this.seen,
        day: day ?? this.day,
        sentToday: sentToday ?? this.sentToday,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'on': enabled,
    'r': radiusM,
    // Solo le ultime 300 promozioni già avvisate.
    's': seen.length > 300 ? seen.toList().sublist(seen.length - 300) : seen.toList(),
    'd': day,
    'n': sentToday,
  };

  static PromoAlertState fromJson(Object? j) {
    if (j is! Map) return const PromoAlertState();
    final int r = (j['r'] as num?)?.toInt() ?? 1000;
    return PromoAlertState(
      enabled: j['on'] == true,
      radiusM: radiusOptions.contains(r) ? r : 1000,
      seen: <String>{for (final Object? x in (j['s'] as List<dynamic>? ?? const <dynamic>[])) '$x'},
      day: '${j['d'] ?? ''}',
      sentToday: (j['n'] as num?)?.toInt() ?? 0,
    );
  }
}

abstract class PromoAlertStore {
  Future<PromoAlertState> load();

  Future<void> save(PromoAlertState state);
}

class MemoryPromoAlertStore implements PromoAlertStore {
  PromoAlertState state = const PromoAlertState();

  @override
  Future<PromoAlertState> load() async => state;

  @override
  Future<void> save(PromoAlertState s) async => state = s;
}

class FilePromoAlertStore implements PromoAlertStore {
  Future<File> _file() async => File('${(await getApplicationDocumentsDirectory()).path}/piazly_avvisi_promo.json');

  @override
  Future<PromoAlertState> load() async {
    try {
      final File f = await _file();
      if (!await f.exists()) return const PromoAlertState();
      return PromoAlertState.fromJson(jsonDecode(await f.readAsString()));
    } catch (_) {
      return const PromoAlertState();
    }
  }

  @override
  Future<void> save(PromoAlertState s) async {
    await (await _file()).writeAsString(jsonEncode(s.toJson()), flush: true);
  }
}

/// Mostra un avviso (titolo, testo). Nell'app: notifica del telefono; nei test: finta.
typedef PromoNotify = Future<void> Function(int id, String title, String body);

double _meters(double lat1, double lng1, double lat2, double lng2) {
  double r(double d) => d * math.pi / 180;
  final double a = math.pow(math.sin(r(lat2 - lat1) / 2), 2) +
      math.cos(r(lat1)) * math.cos(r(lat2)) * math.pow(math.sin(r(lng2 - lng1) / 2), 2);
  return 6371000 * 2 * math.asin(math.sqrt(a));
}

class PromoAlerts extends ChangeNotifier {
  PromoAlerts({required this.notify, PromoAlertStore? store, DateTime Function()? clock})
    : store = store ?? MemoryPromoAlertStore(),
      _clock = clock ?? DateTime.now;

  final PromoNotify notify;
  final PromoAlertStore store;
  final DateTime Function() _clock;
  PromoAlertState _state = const PromoAlertState();
  bool _loaded = false;
  bool _disposed = false;

  PromoAlertState get state => _state;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    _state = await store.load();
    if (!_disposed) notifyListeners();
  }

  Future<void> _set(PromoAlertState s) async {
    _state = s;
    if (!_disposed) notifyListeners();
    try {
      await store.save(s);
    } catch (_) {
      // Preferenza non salvata: resta per questa volta.
    }
  }

  Future<void> setEnabled(bool on) async {
    await load();
    await _set(_state.copyWith(enabled: on));
  }

  Future<void> setRadius(int meters) async {
    await load();
    if (PromoAlertState.radiusOptions.contains(meters)) await _set(_state.copyWith(radiusM: meters));
  }

  static String _dayKey(DateTime t) => '${t.year}-${t.month}-${t.day}';

  /// Avvisa delle promozioni in corso entro il raggio scelto. Restituisce quante.
  Future<int> consider(List<Promotion> promos, double lat, double lng) async {
    await load();
    if (!_state.enabled) return 0;
    final DateTime now = _clock();
    final String today = _dayKey(now);
    int sent = _state.day == today ? _state.sentToday : 0;
    final Set<String> seen = <String>{..._state.seen};
    int shown = 0;
    final List<(Promotion, double)> near = <(Promotion, double)>[
      for (final Promotion p in promos)
        if (!p.mine && p.isLive(now) && !seen.contains(p.id))
          (p, _meters(lat, lng, p.lat, p.lng)),
    ]..sort(((Promotion, double) a, (Promotion, double) b) {
        final int d = a.$2.compareTo(b.$2);
        return d != 0 ? d : a.$1.id.compareTo(b.$1.id);
      });
    for (final (Promotion, double) n in near) {
      if (n.$2 > _state.radiusM || sent >= PromoAlertState.maxPerDay) break;
      final Promotion p = n.$1;
      final int m = n.$2 < 1000 ? (n.$2 / 50).round() * 50 : n.$2.round();
      final String where = n.$2 < 1000 ? 'a $m m' : 'a ${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
      try {
        await notify(
          p.id.hashCode & 0x3fffffff,
          '${p.kind == PromotionKind.evento ? '📅' : '🏷️'} ${p.businessName} $where',
          '${p.title}${p.hasCoupon ? ' · coupon: ${p.couponText}' : ''}',
        );
      } catch (_) {
        continue;
      }
      seen.add(p.id);
      sent++;
      shown++;
    }
    if (shown > 0 || _state.day != today) {
      await _set(_state.copyWith(seen: seen, day: today, sentToday: sent));
    }
    return shown;
  }

  /// Controllo con Piazly aperta: ultima posizione nota del telefono (senza accendere il GPS).
  Future<void> checkNow(BusinessRepository repo) async {
    await load();
    if (!_state.enabled) return;
    try {
      final LocationPermission p = await Geolocator.checkPermission();
      if (p != LocationPermission.always && p != LocationPermission.whileInUse) return;
      final Position? pos = await Geolocator.getLastKnownPosition();
      if (pos == null) return;
      final List<Promotion> promos = await repo.promotionsNearby(
        pos.latitude,
        pos.longitude,
        radiusKm: (_state.radiusM / 1000).ceil(),
      );
      await consider(promos, pos.latitude, pos.longitude);
    } catch (_) {
      // Niente avvisi questa volta.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

abstract final class PromoAlertsRegistry {
  static PromoAlerts? current;
}

/// Controlla quando l'app torna in primo piano e ogni 10 minuti mentre è aperta.
class PromoAlertsWatcher with WidgetsBindingObserver {
  PromoAlertsWatcher(this.alerts, this.repository);

  final PromoAlerts alerts;
  final BusinessRepository repository;
  Timer? _timer;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _tick();
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => _tick());
  }

  void _tick() => unawaited(alerts.checkNow(repository));

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tick();
      _timer ??= Timer.periodic(const Duration(minutes: 10), (_) => _tick());
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
      _timer = null;
    }
  }
}

/// Interruttore e raggio degli avvisi (Promozioni, I miei coupon).
class PromoAlertsTile extends StatefulWidget {
  const PromoAlertsTile({super.key, this.alerts});

  final PromoAlerts? alerts;

  @override
  State<PromoAlertsTile> createState() => _PromoAlertsTileState();
}

class _PromoAlertsTileState extends State<PromoAlertsTile> {
  PromoAlerts? get _a => widget.alerts ?? PromoAlertsRegistry.current;

  @override
  void initState() {
    super.initState();
    unawaited(_a?.load());
  }

  String _label(int m) => m < 1000 ? '$m m' : '${m ~/ 1000} km';

  @override
  Widget build(BuildContext context) {
    final PromoAlerts? a = _a;
    if (a == null) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    return ListenableBuilder(
      listenable: a,
      builder: (BuildContext context, _) {
        final PromoAlertState s = a.state;
        return SoftCard(
          key: const ValueKey<String>('avvisi_promo'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                key: const ValueKey<String>('avvisi_promo_interruttore'),
                contentPadding: EdgeInsets.zero,
                value: s.enabled,
                onChanged: (bool v) => unawaited(a.setEnabled(v)),
                title: const Text('Avvisami delle promozioni vicine'),
                subtitle: Text(
                  'Con Piazly aperta, al massimo ${PromoAlertState.maxPerDay} avvisi al giorno. '
                  'La tua posizione resta sul telefono.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (s.enabled)
                Wrap(
                  spacing: 8,
                  children: [
                    for (final int m in PromoAlertState.radiusOptions)
                      ChoiceChip(
                        key: ValueKey<String>('avvisi_raggio_$m'),
                        label: Text('Entro ${_label(m)}'),
                        selected: s.radiusM == m,
                        onSelected: (_) => unawaited(a.setRadius(m)),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

