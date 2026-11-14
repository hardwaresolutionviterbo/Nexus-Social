import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Configurazione Firebase per iOS (regole F10 e F8).
///
/// Il file GoogleService-Info.plist non sta nel repository: la build iOS su Codemagic lo
/// crea da un segreto dopo i test. Il progetto Xcode deve comunque includerlo nel bundle.
void main() {
  const String plistPath = 'ios/Runner/GoogleService-Info.plist';
  final String pbxproj = File(
    'ios/Runner.xcodeproj/project.pbxproj',
  ).readAsStringSync();

  test('iOS · il plist Firebase non è nel repository e resta escluso da Git', () {
    expect(File(plistPath).existsSync(), isFalse);
    final List<String> ignored = File('.gitignore').readAsLinesSync();
    expect(ignored, contains(plistPath));
    expect(ignored, contains('android/app/google-services.json'));
  });

  test('iOS · il progetto Xcode include GoogleService-Info.plist nel target Runner', () {
    final RegExp fileRef = RegExp(
      r'(\w{24}) /\* GoogleService-Info\.plist \*/ = \{isa = PBXFileReference;'
      r'[^}]*path = "GoogleService-Info\.plist"; sourceTree = "<group>"; \};',
    );
    final Match? ref = fileRef.firstMatch(pbxproj);
    expect(ref, isNotNull, reason: 'riferimento al file');

    // Nel gruppo Runner (percorso ios/Runner).
    final String runnerGroup = RegExp(
      r'/\* Runner \*/ = \{\s*isa = PBXGroup;[\s\S]*?path = Runner;',
    ).firstMatch(pbxproj)!.group(0)!;
    expect(runnerGroup, contains('${ref!.group(1)} /* GoogleService-Info.plist */'));

    // Copiato tra le risorse dell'app.
    final RegExp buildFile = RegExp(
      r'(\w{24}) /\* GoogleService-Info\.plist in Resources \*/ = \{isa = PBXBuildFile; '
      'fileRef = ${ref.group(1)} ',
    );
    final Match? build = buildFile.firstMatch(pbxproj);
    expect(build, isNotNull, reason: 'file di build');
    final String resources = RegExp(
      r'/\* Begin PBXResourcesBuildPhase section \*/[\s\S]*?/\* End PBXResourcesBuildPhase section \*/',
    ).firstMatch(pbxproj)!.group(0)!;
    expect(resources, contains('${build!.group(1)} /* GoogleService-Info.plist in Resources */'));
  });

  test('iOS · dipendenze solo con Swift Package Manager, nessun CocoaPods', () {
    // Un Podfile farebbe integrare CocoaPods da Flutter accanto a SPM (integrazione mista).
    expect(File('ios/Podfile').existsSync(), isFalse);
    expect(File('ios/Podfile.lock').existsSync(), isFalse);
    expect(pbxproj, isNot(contains('[CP]')));
    expect(pbxproj, isNot(contains('Pods_Runner')));
    expect(pbxproj, isNot(contains('Pods-Runner')));
    for (final String config in <String>['Debug', 'Release']) {
      expect(
        File('ios/Flutter/$config.xcconfig').readAsStringSync(),
        isNot(contains('Pods')),
        reason: config,
      );
    }
    // Pacchetto Swift generato da Flutter collegato al target Runner.
    expect(
      pbxproj,
      contains(
        'XCLocalSwiftPackageReference "Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage"',
      ),
    );
    expect(pbxproj, contains('FlutterGeneratedPluginSwiftPackage in Frameworks'));
    // Versione minima iOS 15 (prima indicata nel Podfile).
    final Set<String> targets = RegExp(
      r'IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);',
    ).allMatches(pbxproj).map((Match m) => m.group(1)!).toSet();
    expect(targets, <String>{'15.0'});
  });

  test('iOS · Bundle ID dell\'app: com.nexussocial.app (come in Firebase)', () {
    final Iterable<String> ids = RegExp(
      r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);',
    ).allMatches(pbxproj).map((Match m) => m.group(1)!);
    expect(ids.where((String id) => !id.endsWith('.RunnerTests')).toSet(), <String>{
      'com.nexussocial.app',
    });
  });
}
