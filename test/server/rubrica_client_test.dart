import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_social/features/contacts/contacts_sync.dart';

/// La rubrica ora passa dalla funzione `rubrica` di Supabase: messaggi chiari per gli errori.
void main() {
  test('errori della funzione rubrica in parole semplici', () {
    expect(rubricaErrorMessage(429), 'Hai già sincronizzato 3 volte oggi. Riprova domani.');
    expect(rubricaErrorMessage(503), 'La rubrica non è ancora disponibile.');
    expect(rubricaErrorMessage(401), contains('Accesso scaduto'));
    expect(rubricaErrorMessage(500), 'Sincronizzazione non riuscita. Riprova più tardi.');
  });
}
