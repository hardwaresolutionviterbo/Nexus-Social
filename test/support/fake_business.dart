import 'dart:typed_data';

import 'package:nexus_social/features/business/business_models.dart';
import 'package:nexus_social/features/business/business_repository.dart';
import 'package:nexus_social/features/profile/profile_models.dart';

/// Aziende in memoria, con gli stessi controlli principali del server.
class FakeBusinessRepository implements BusinessRepository {
  FakeBusinessRepository({this.me = 'utenteAnna000000000000000001'});

  final String me;
  final Map<String, MyBusiness> registered = <String, MyBusiness>{};
  final Map<String, BusinessPage> pages = <String, BusinessPage>{};
  final Map<String, String> usernames = <String, String>{};
  final Map<String, Uint8List> files = <String, Uint8List>{};
  final Map<String, BusinessSubscription> subscriptions = <String, BusinessSubscription>{};
  final Set<String> trialVats = <String>{};
  DateTime Function() clock = DateTime.now;
  int _n = 0;
  double? askedLat;

  bool _active(String id) => subscriptions[id]?.isActive(clock()) ?? false;

  /// Badge: approvata e con Premium attivo.
  bool badge(String id) => registered[id]?.status == VerificationStatus.verified && _active(id);

  BusinessSubscription _sub(String id) {
    final BusinessSubscription s = subscriptions[id] ?? const BusinessSubscription();
    final bool used = trialVats.contains(registered[id]?.vatNumber);
    return BusinessSubscription(periodEnd: s.periodEnd, source: s.source, trialUsed: used || s.trialUsed);
  }

  @override
  Future<MyBusiness?> mine() async {
    final MyBusiness? b = registered[me];
    if (b == null) return null;
    return MyBusiness(
      businessName: b.businessName,
      vatNumber: b.vatNumber,
      status: b.status,
      reviewNote: b.reviewNote,
      hasDocument: b.hasDocument,
      page: pages[me],
      verifiedBadge: badge(me),
      subscription: _sub(me),
    );
  }

  @override
  Future<BusinessSubscription> startTrial() async {
    final MyBusiness? b = registered[me];
    if (b == null) throw const BusinessFailure('Registra prima l\'azienda.');
    if (_sub(me).trialUsed) throw const BusinessFailure('La prova gratuita è già stata usata.');
    if (_active(me)) throw const BusinessFailure('L\'abbonamento è già attivo.');
    trialVats.add(b.vatNumber);
    subscriptions[me] = BusinessSubscription(
      periodEnd: clock().add(const Duration(days: 7)),
      source: 'trial',
      trialUsed: true,
    );
    return _sub(me);
  }

  @override
  Future<void> adminExtendSubscription(String id, {int months = 1}) async {
    final DateTime now = clock();
    final DateTime? end = subscriptions[id]?.periodEnd;
    final DateTime from = end != null && end.isAfter(now) ? end : now;
    subscriptions[id] = BusinessSubscription(
      periodEnd: DateTime(from.year, from.month + months, from.day, from.hour, from.minute),
      source: 'admin',
    );
  }

  @override
  Future<void> adminStopSubscription(String id) async {
    final BusinessSubscription? s = subscriptions[id];
    if (s != null) subscriptions[id] = BusinessSubscription(periodEnd: clock(), source: s.source);
  }

  @override
  Future<void> register({required String businessName, required String vatNumber}) async {
    final String vat = vatNumber.replaceAll(' ', '');
    if (!ProfileRules.isValidPartitaIva(vat)) throw const BusinessFailure('Partita IVA non valida.');
    if (registered.entries.any((MapEntry<String, MyBusiness> e) => e.key != me && e.value.vatNumber == vat)) {
      throw const BusinessFailure('Questa partita IVA è già registrata su Piazly.');
    }
    final MyBusiness? old = registered[me];
    final bool changed = old == null || old.businessName != businessName.trim() || old.vatNumber != vat;
    registered[me] = MyBusiness(
      businessName: businessName.trim(),
      vatNumber: vat,
      status: changed ? VerificationStatus.pending : old.status,
      hasDocument: old?.hasDocument ?? false,
      reviewNote: changed ? '' : old.reviewNote,
    );
  }

  @override
  Future<void> savePage(BusinessPageDraft d, {List<Uint8List> newPhotos = const <Uint8List>[]}) async {
    if (registered[me] == null) throw const BusinessFailure('Registra prima l\'azienda.');
    if (!d.inItaly) throw const BusinessFailure('La sede deve essere in Italia.');
    final List<String> photos = <String>[...d.keptPhotos];
    for (final Uint8List b in newPhotos) {
      final String path = '$me/foto-${(++_n).toString().padLeft(8, '0')}.jpg';
      files[path] = b;
      photos.add(path);
    }
    pages[me] = BusinessPage(
      id: me,
      displayName: d.displayName.trim(),
      category: d.category,
      address: d.address,
      lat: d.lat,
      lng: d.lng,
      description: d.description.trim(),
      phone: d.phone.trim(),
      bookingUrl: d.bookingUrl.trim(),
      hours: d.hours,
      photos: photos,
      published: d.published,
    );
  }

  @override
  Future<void> setDocument(Uint8List bytes, {required bool pdf}) async {
    final MyBusiness b = registered[me]!;
    final String path = '$me/documento-${(++_n).toString().padLeft(8, '0')}.${pdf ? 'pdf' : 'jpg'}';
    files[path] = bytes;
    registered[me] = MyBusiness(
      businessName: b.businessName,
      vatNumber: b.vatNumber,
      status: b.status,
      reviewNote: b.reviewNote,
      hasDocument: true,
    );
  }

  @override
  Future<BusinessPage?> page(String id) async {
    final BusinessPage? p = pages[id];
    if (p == null || (!p.published && id != me)) return null;
    return BusinessPage(
      id: p.id,
      displayName: p.displayName,
      category: p.category,
      address: p.address,
      lat: p.lat,
      lng: p.lng,
      description: p.description,
      phone: p.phone,
      bookingUrl: p.bookingUrl,
      hours: p.hours,
      photos: p.photos,
      published: p.published,
      verified: badge(id),
      username: usernames[id] ?? '',
      mine: id == me,
    );
  }

  @override
  Future<List<BusinessPin>> nearby(double lat, double lng, {int radiusKm = 20}) async {
    askedLat = lat;
    return <BusinessPin>[
      for (final BusinessPage p in pages.values)
        if (p.published && (p.lat - lat).abs() < radiusKm / 111 && (p.lng - lng).abs() < radiusKm / 80)
          BusinessPin(
            id: p.id,
            displayName: p.displayName,
            category: p.category,
            lat: p.lat,
            lng: p.lng,
            verified: badge(p.id),
          ),
    ];
  }

  @override
  Future<Uint8List?> photo(String path) async => files[path];

  @override
  Future<List<BusinessReviewItem>> reviewQueue() async => <BusinessReviewItem>[
    for (final MapEntry<String, MyBusiness> e in registered.entries)
      BusinessReviewItem(
        id: e.key,
        username: usernames[e.key] ?? 'utente',
        businessName: e.value.businessName,
        vatNumber: e.value.vatNumber,
        status: e.value.status,
        displayName: pages[e.key]?.displayName ?? '',
        city: pages[e.key]?.address.city ?? '',
        province: pages[e.key]?.address.province ?? '',
        subscriptionEnd: subscriptions[e.key]?.periodEnd,
        subscriptionSource: subscriptions[e.key]?.source ?? '',
      ),
  ];

  @override
  Future<void> review(String id, {required bool approve, String note = ''}) async {
    final MyBusiness b = registered[id]!;
    registered[id] = MyBusiness(
      businessName: b.businessName,
      vatNumber: b.vatNumber,
      status: approve ? VerificationStatus.verified : VerificationStatus.rejected,
      reviewNote: note.trim(),
      hasDocument: b.hasDocument,
    );
  }

  @override
  Future<Uint8List?> document(String path) async => files[path];

  /// Un'attività già pronta (per le prove della Mappa e delle anteprime).
  void seed({
    required String id,
    required String username,
    required String name,
    required BusinessCategory category,
    required BusinessAddress address,
    required double lat,
    required double lng,
    VerificationStatus status = VerificationStatus.pending,
    DateTime? premiumUntil,
    BusinessHours hours = const BusinessHours(),
    String description = '',
    String phone = '',
    String bookingUrl = '',
  }) {
    usernames[id] = username;
    registered[id] = MyBusiness(businessName: '$name S.r.l.', vatNumber: '12345678903', status: status);
    if (premiumUntil != null) subscriptions[id] = BusinessSubscription(periodEnd: premiumUntil, source: 'admin');
    pages[id] = BusinessPage(
      id: id,
      displayName: name,
      category: category,
      address: address,
      lat: lat,
      lng: lng,
      hours: hours,
      description: description,
      phone: phone,
      bookingUrl: bookingUrl,
    );
  }
}
