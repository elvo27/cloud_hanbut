import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hanbut/ads/ad_service.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  static final Uri _policyUri = Uri.parse(
    'https://elvo27.github.io/cloud_hanbut/privacy-policy-ko.html',
  );
  static final Uri _contactUri = Uri(
    scheme: 'mailto',
    path: 'elvo27@gmail.com',
    queryParameters: <String, String>{'subject': '구름 친구 맺기 문의'},
  );

  Future<void> _open(BuildContext context, Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('링크를 열 수 없어요. 잠시 후 다시 시도해주세요.')),
      );
    }
  }

  Future<void> _showAdPrivacy(BuildContext context) async {
    final String? error = await AdService.instance.showPrivacyOptions();
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error == null ? '광고 개인정보 선택 사항을 확인했어요.' : '현재 광고 개인정보 설정을 열 수 없어요.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('개인정보 및 광고 설정')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '데이터 이용 안내',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '게임 기록은 기기에 저장됩니다. 공개 랭킹 등록을 선택하면 닉네임, '
                      '점수, 스테이지와 기록 시간이 Supabase 서버로 전송됩니다. 광고는 '
                      'Google AdMob을 사용하며 아동 대상·G등급으로 제한해 요청합니다.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('개인정보처리방침 전문'),
              subtitle: const Text('수집 항목, 이용 목적, 보관 및 삭제 안내'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _open(context, _policyUri),
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('광고 개인정보 선택'),
              subtitle: const Text('지역에 따라 Google 동의 선택 화면이 표시됩니다.'),
              onTap: () => _showAdPrivacy(context),
            ),
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('기록 삭제·신고 및 문의'),
              subtitle: const Text('elvo27@gmail.com'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _open(context, _contactUri),
            ),
          ],
        ),
      ),
    );
  }
}
