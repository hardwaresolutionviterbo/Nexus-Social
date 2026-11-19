import 'package:material_ui/material_ui.dart';

import '../map/map_screen.dart';
import '../map/social_repository.dart';
import 'market_models.dart';
import 'market_repository.dart';
import 'market_section_screen.dart';

/// Scheda «Vendita» della barra: contiene anche «Scambia» (decisione del titolare, 19/11/2026).
/// La grafica definitiva arriverà con i mockup del titolare.
class SaleAndSwapScreen extends StatefulWidget {
  const SaleAndSwapScreen({super.key, this.repository, this.services, this.social});

  final MarketRepository? repository;
  final MapServices? services;
  final SocialRepository? social;

  @override
  State<SaleAndSwapScreen> createState() => _SaleAndSwapScreenState();
}

class _SaleAndSwapScreenState extends State<SaleAndSwapScreen> {
  MarketSection _section = MarketSection.sale;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: SegmentedButton<MarketSection>(
            key: const ValueKey<String>('vendita_sezioni'),
            showSelectedIcon: false,
            segments: const <ButtonSegment<MarketSection>>[
              ButtonSegment<MarketSection>(
                value: MarketSection.sale,
                icon: Icon(Icons.sell_outlined),
                label: Text('Vendita', key: ValueKey<String>('sezione_vendita')),
              ),
              ButtonSegment<MarketSection>(
                value: MarketSection.swap,
                icon: Icon(Icons.swap_horiz_rounded),
                label: Text('Scambia', key: ValueKey<String>('sezione_scambia')),
              ),
            ],
            selected: <MarketSection>{_section},
            onSelectionChanged: (Set<MarketSection> v) => setState(() => _section = v.first),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _section == MarketSection.sale ? 0 : 1,
            children: [
              MarketSectionScreen(
                section: MarketSection.sale,
                repository: widget.repository,
                services: widget.services,
                social: widget.social,
              ),
              MarketSectionScreen(
                section: MarketSection.swap,
                repository: widget.repository,
                services: widget.services,
                social: widget.social,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
