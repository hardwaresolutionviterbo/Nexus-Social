import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import 'listing_models.dart';
import 'map_location.dart';
import 'map_surface.dart';

/// Scelta a mano del punto di un annuncio (bar, punto d'incontro): si sposta la mappa
/// sotto il segnaposto fisso al centro. Il punto vale solo per quell'annuncio e non cambia
/// la posizione del telefono.
class PointPickerScreen extends StatefulWidget {
  const PointPickerScreen({super.key, required this.surface, this.start});

  final MapSurfaceBuilder surface;

  /// Dove aprire la mappa: punto già scelto o posizione attuale.
  final GeoPoint? start;

  @override
  State<PointPickerScreen> createState() => _PointPickerScreenState();
}

class _PointPickerScreenState extends State<PointPickerScreen> {
  MapSurfaceHandle? _handle;
  bool _busy = false;

  void _onReady(MapSurfaceHandle handle) {
    _handle = handle;
    final GeoPoint? start = widget.start;
    if (start != null) {
      unawaited(
        handle.flyTo(
          GeoFix(latitude: start.latitude, longitude: start.longitude, time: DateTime.now()),
          threeD: false,
        ),
      );
    }
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    final GeoPoint? point = await _handle?.center();
    if (!mounted) return;
    setState(() => _busy = false);
    if (point != null) Navigator.of(context).pop(point);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scegli il punto')),
      body: Stack(
        children: [
          Positioned.fill(child: widget.surface(context, _onReady)),
          // Segnaposto fisso: la punta indica il centro della mappa.
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 44),
                child: Icon(Icons.location_on, size: 48, color: AppColors.brandOrangeDeep),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Material(
              color: theme.colorScheme.surface,
              elevation: 4,
              borderRadius: BorderRadius.circular(22),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Sposta la mappa fino a mettere il segnaposto sul bar o sul punto '
                      'd\'incontro. Gli altri vedranno esattamente questo punto: non '
                      'scegliere casa tua.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _busy ? null : _confirm,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Usa questo punto'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
