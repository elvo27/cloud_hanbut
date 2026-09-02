import 'dart:io';

import 'package:flutter/foundation.dart';

/// AdMob identifiers are public configuration values, not secret keys.
///
/// TestFlight builds are produced with `--dart-define=USE_TEST_ADS=true` so
/// testers cannot generate invalid traffic on the production ad units.
abstract final class AdIds {
  static const bool adsEnabled = bool.fromEnvironment(
    'ADS_ENABLED',
    defaultValue: true,
  );

  static const bool useTestAds = bool.fromEnvironment(
    'USE_TEST_ADS',
    defaultValue: !kReleaseMode,
  );

  static bool get isSupportedPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static String get banner {
    if (useTestAds) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/9214589741'
          : 'ca-app-pub-3940256099942544/2435281174';
    }
    return Platform.isAndroid
        ? 'ca-app-pub-6883694824773197/3167726950'
        : 'ca-app-pub-6883694824773197/9530060526';
  }

  static String get interstitial {
    if (useTestAds) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/1033173712'
          : 'ca-app-pub-3940256099942544/4411468910';
    }
    return Platform.isAndroid
        ? 'ca-app-pub-6883694824773197/8392133479'
        : 'ca-app-pub-6883694824773197/8583705163';
  }

  static String get rewarded {
    if (useTestAds) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/5224354917'
          : 'ca-app-pub-3940256099942544/1712485313';
    }
    return Platform.isAndroid
        ? 'ca-app-pub-6883694824773197/1778246366'
        : 'ca-app-pub-6883694824773197/8343654717';
  }
}
