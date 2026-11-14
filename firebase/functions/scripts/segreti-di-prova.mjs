// Segreti SOLO per gli emulatori locali (progetto fittizio demo-nexus-social): chiave dei
// vettori di prova RFC 9497 e una chiave di firma inventata. Il file non va nel repository.
import { writeFileSync } from 'node:fs';

writeFileSync(
  '.secret.local',
  [
    'OPRF_KEY=159749d750713afe245d2d39ccfaae8381c53ce92d098a9375ee70739c7ac0bf',
    'RUBRICA_ATTEST_KEY=chiave-di-firma-solo-per-emulatori-0123456789',
    '',
  ].join('\n'),
);
console.log('Segreti di prova scritti per gli emulatori.');
