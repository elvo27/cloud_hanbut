import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:hanbut/ads/ad_ids.dart';

class AdService extends ChangeNotifier {
  AdService._();

  static final AdService instance = AdService._();

  bool _initializationStarted = false;
  bool _mobileAdsInitialized = false;
  bool _canRequestAds = false;
  bool _privacyOptionsRequired = false;

  bool get canShowAds =>
      AdIds.adsEnabled &&
      AdIds.isSupportedPlatform &&
      _mobileAdsInitialized &&
      _canRequestAds;

  bool get privacyOptionsRequired => _privacyOptionsRequired;

  Future<void> initialize() async {
    if (_initializationStarted ||
        !AdIds.adsEnabled ||
        !AdIds.isSupportedPlatform) {
      return;
    }
    _initializationStarted = true;

    // The app is suitable for all ages. Until a separate neutral age screen is
    // introduced, every request receives the most conservative child-directed
    // and under-age treatment and only G-rated ad inventory is allowed.
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        tagForChildDirectedTreatment: TagForChildDirectedTreatment.yes,
        tagForUnderAgeOfConsent: TagForUnderAgeOfConsent.yes,
        maxAdContentRating: MaxAdContentRating.g,
      ),
    );

    final Completer<void> completer = Completer<void>();
    final ConsentRequestParameters parameters = ConsentRequestParameters(
      tagForUnderAgeOfConsent: true,
    );

    ConsentInformation.instance.requestConsentInfoUpdate(
      parameters,
      () {
        ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) async {
          if (error != null) {
            debugPrint(
              'Ad consent form error: ${error.errorCode} ${error.message}',
            );
          }
          await _refreshConsentState();
          if (!completer.isCompleted) {
            completer.complete();
          }
        });
      },
      (FormError error) async {
        debugPrint(
          'Ad consent update error: ${error.errorCode} ${error.message}',
        );
        // A previous valid consent state may still allow ad requests.
        await _refreshConsentState();
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );

    await completer.future;
  }

  Future<void> _refreshConsentState() async {
    _privacyOptionsRequired =
        await ConsentInformation.instance
            .getPrivacyOptionsRequirementStatus() ==
        PrivacyOptionsRequirementStatus.required;
    _canRequestAds = await ConsentInformation.instance.canRequestAds();

    if (_canRequestAds && !_mobileAdsInitialized) {
      await MobileAds.instance.initialize();
      _mobileAdsInitialized = true;
    }
    notifyListeners();
  }

  Future<String?> showPrivacyOptions() async {
    if (!AdIds.isSupportedPlatform) {
      return null;
    }

    final Completer<String?> completer = Completer<String?>();
    ConsentForm.showPrivacyOptionsForm((FormError? error) async {
      await _refreshConsentState();
      completer.complete(
        error == null ? null : '${error.errorCode}: ${error.message}',
      );
    });
    return completer.future;
  }
}
