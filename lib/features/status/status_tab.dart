import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../chat/chat_service.dart';
import '../profile/profile_repository.dart';
import 'status_screens.dart';

/// Scheda «Stati» della barra in basso (decisione del titolare, 19/11/2026): pubblicare e
/// guardare gli aggiornamenti di 24 ore.
class StatusTab extends StatelessWidget {
  const StatusTab({super.key, this.chat, this.profiles, this.picker});

  final ChatService? chat;
  final ProfileRepository? profiles;
  final StatusPicker? picker;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ChatService? c = chat;
    if (c == null || c.statuses == null) {
      return ListView(
        padding: AppSpacing.pagePadding,
        children: [
          Text('Stati dei tuoi contatti', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Testo, foto o video che durano 24 ore. Scegli tu chi li vede. Disponibili con '
            'l\'account collegato.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      );
    }
    return StatusList(service: c.statuses!, contacts: c.contacts, profiles: profiles, picker: picker);
  }
}
