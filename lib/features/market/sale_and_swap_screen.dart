import 'package:material_ui/material_ui.dart';

import '../map/map_screen.dart';
import '../map/social_repository.dart';
import 'market_models.dart';
import 'market_repository.dart';
import 'market_section_screen.dart';

/// Scheda «Vendita» della barra: Scambia e Vendi in una sola schermata (mockup del titolare,
/// 19/11/2026), con i filtri Tutti, Scambio, Vendita e Regalo.
class SaleAndSwapScreen extends StatelessWidget {
  const SaleAndSwapScreen({super.key, this.repository, this.services, this.social});

  final MarketRepository? repository;
  final MapServices? services;
  final SocialRepository? social;

  static final ValueNotifier<int> _search = ValueNotifier<int>(0);

  /// La lente dell'intestazione: porta il cursore nella ricerca degli annunci.
  static void requestSearch() => _search.value++;

  @override
  Widget build(BuildContext context) => MarketSectionScreen(
    section: MarketSection.sale,
    unified: true,
    repository: repository,
    services: services,
    social: social,
    searchRequests: _search,
  );
}
