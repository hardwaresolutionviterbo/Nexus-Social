import 'package:nexus_social/features/market/comuni_italia.dart';

/// Pochi comuni veri, per i test (l'app usa l'elenco completo ISTAT).
ComuniItalia fakeComuni() => ComuniItalia.fromJson(<String, dynamic>{
  'regioni': <String>['Lazio', 'Lombardia', 'Umbria'],
  'province': <List<Object>>[
    <Object>['MI', 'Milano', 1],
    <Object>['RM', 'Roma', 0],
    <Object>['TR', 'Terni', 2],
    <Object>['VT', 'Viterbo', 0],
  ],
  'comuni': <List<Object>>[
    <Object>['Milano', 0, 45.4642, 9.19],
    <Object>['Roma', 1, 41.8933, 12.4829],
    <Object>['Porano', 2, 42.6843, 12.1037],
    <Object>['Viterbo', 3, 42.4207, 12.1077],
  ],
});
