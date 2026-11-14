import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'contacts_sync.dart';

/// Aggiorna la rubrica da sola, come WhatsApp (solo con il consenso attivo):
/// all'apertura dell'app, quando si torna nell'app e quando la rubrica del telefono cambia
/// (per esempio dopo aver salvato un nuovo contatto). Il controllo vero lo fa
/// [ContactsRepository.autoSyncIfNeeded]: subito se la rubrica è cambiata, altrimenti al
/// massimo una volta al giorno, sempre entro i 3 aggiornamenti al giorno.
class ContactsAutoSync extends StatefulWidget {
  const ContactsAutoSync({
    super.key,
    required this.repository,
    required this.child,
    this.debounce = const Duration(seconds: 3),
  });

  final ContactsRepository repository;
  final Widget child;
  final Duration debounce;

  @override
  State<ContactsAutoSync> createState() => _ContactsAutoSyncState();
}

class _ContactsAutoSyncState extends State<ContactsAutoSync> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.repository.watchContacts(_onContactsChanged);
    _run();
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.repository.unwatchContacts(_onContactsChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _run();
  }

  void _onContactsChanged() {
    _timer?.cancel();
    _timer = Timer(widget.debounce, _run);
  }

  void _run() {
    widget.repository.autoSyncIfNeeded();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
