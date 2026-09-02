import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:hanbut/ads/ad_ids.dart';
import 'package:hanbut/ads/ad_service.dart';

enum BannerPlacement { home, myScores, leaderboard }

class SafeBannerAd extends StatefulWidget {
  const SafeBannerAd({
    super.key,
    required this.placement,
    this.horizontalPadding = 0,
  });

  final BannerPlacement placement;
  final double horizontalPadding;

  @override
  State<SafeBannerAd> createState() => _SafeBannerAdState();
}

class _SafeBannerAdState extends State<SafeBannerAd> {
  BannerAd? _banner;
  double? _requestedWidth;
  bool _loadInProgress = false;
  bool _loadAttempted = false;

  @override
  void initState() {
    super.initState();
    AdService.instance.addListener(_handleAdServiceChanged);
  }

  @override
  void dispose() {
    AdService.instance.removeListener(_handleAdServiceChanged);
    unawaited(_banner?.dispose());
    super.dispose();
  }

  void _handleAdServiceChanged() {
    if (!mounted) {
      return;
    }
    if (AdService.instance.canShowAds && _banner == null) {
      _loadAttempted = false;
    }
    setState(() {});
  }

  Future<void> _load(double availableWidth) async {
    if (_loadInProgress ||
        _loadAttempted ||
        !AdService.instance.canShowAds ||
        availableWidth <= 0) {
      return;
    }

    _loadInProgress = true;
    _loadAttempted = true;
    _requestedWidth = availableWidth;

    final AdSize? size =
        await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
          availableWidth.truncate(),
        );
    if (!mounted || size == null) {
      _loadInProgress = false;
      return;
    }

    final BannerAd banner = BannerAd(
      adUnitId: AdIds.banner,
      request: const AdRequest(),
      size: size,
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) {
          if (!mounted) {
            unawaited(ad.dispose());
            return;
          }
          setState(() {
            _banner = ad as BannerAd;
            _loadInProgress = false;
          });
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          debugPrint(
            'Banner ${widget.placement.name} failed: '
            '${error.code} ${error.message}',
          );
          unawaited(ad.dispose());
          if (mounted) {
            setState(() {
              _loadInProgress = false;
            });
          }
        },
      ),
    );
    banner.load();
  }

  @override
  Widget build(BuildContext context) {
    if (!AdIds.adsEnabled || !AdIds.isSupportedPlatform) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double availableWidth =
            constraints.maxWidth - widget.horizontalPadding * 2;
        final double reservedHeight = availableWidth >= 600 ? 108 : 70;
        if (_requestedWidth != null &&
            (_requestedWidth! - availableWidth).abs() >= 24) {
          unawaited(_banner?.dispose());
          _banner = null;
          _loadAttempted = false;
          _requestedWidth = null;
        }

        if (_banner == null && AdService.instance.canShowAds) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              unawaited(_load(availableWidth));
            }
          });
        }

        final BannerAd? banner = _banner;
        if (banner == null) {
          // Reserve the final ad area before the asynchronous load completes.
          // This prevents buttons from moving beneath a user's finger.
          return SizedBox(height: reservedHeight);
        }

        return Semantics(
          label: '광고',
          container: true,
          child: SizedBox(
            height: reservedHeight,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.horizontalPadding,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '광고',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.blueGrey.shade400,
                    ),
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    width: banner.size.width.toDouble(),
                    height: banner.size.height.toDouble(),
                    child: AdWidget(ad: banner),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
