#!/usr/bin/env python3
"""
iOS App Store 배포 자동화 스크립트
사용법: 
  python distribute.py --api-key-id YOUR_KEY_ID --api-issuer-id YOUR_ISSUER_ID --team-id YOUR_TEAM_ID --bundle-id com.example.app

앱 이름은 pubspec.yaml의 description에서 자동으로 가져옵니다.
모든 매개변수는 필수입니다. 도움말: python distribute.py --help

=== 사전 준비사항 ===
1. App Store Connect API 키 생성 및 다운로드
2. iOS Distribution 인증서 확인
3. API Key 파일(.p8)을 프로젝트 루트에 위치
4. pubspec.yaml에 올바른 description 설정

자세한 설정 방법은 아래 가이드를 참고하세요.
"""

import argparse
import os
import subprocess
import sys
import yaml
from pathlib import Path

# ==================== 설정 가이드 ====================

# 📝 App Store Connect API 키 준비방법: 
#   1. App Store Connect API 페이지로 이동: https://appstoreconnect.apple.com/access/integrations/api
#   2. "+" 버튼 클릭하여 새 API 키 생성
#   3. 이름: "CLI Upload", 액세스 권한: "앱 관리" 선택
#   4. 생성 후 Key ID, Issuer ID 기록
#   5. .p8 파일 다운로드 (한 번만 다운로드 가능하니 안전한 곳에 보관!)
#   6. 다운로드한 파일을 프로젝트 루트에 위치시키기

# 📝 Team ID 준비방법: 
#   터미널에서 다음 명령어 실행: `security find-identity -v -p codesigning`
#   결과에서 "iPhone Distribution: [이름] ([TEAM_ID])" 형태의 줄에서 TEAM_ID 확인
#   예시: "iPhone Distribution: Seungtae Kim (XXXXXXXXXX)" → Team ID는 "XXXXXXXXXX"

# 📝 Bundle ID 준비방법: 
#   Xcode → TARGETS의 Runner → Signing & Capabilities → Bundle Identifier 확인

# 고정 설정 (일반적으로 수정 불필요)
WORKSPACE_PATH = "ios/Runner.xcworkspace"              # Flutter iOS workspace 경로 (일반적으로 고정)
SCHEME_NAME = "Runner"                                 # Xcode scheme 이름 (Flutter는 보통 "Runner")
ARCHIVE_PATH = "build/Runner.xcarchive"                # 아카이브 파일 생성 경로
IPA_OUTPUT_PATH = "build/ipa"                          # IPA 파일 출력 디렉토리
EXPORT_OPTIONS_PATH = "ios/ExportOptions.plist"       # Export 설정 파일 경로

# API Key 저장 경로 (자동 설정, 수정 불필요)
# altool이 자동으로 인식하는 표준 경로에 API Key 파일을 복사
API_KEY_DIR = os.path.expanduser("~/.appstoreconnect/private_keys")  # altool 표준 API Key 디렉토리

# 전역 변수 (런타임에 설정됨)
API_KEY_ID = None
API_ISSUER_ID = None  
API_KEY_FILENAME = None
API_KEY_PATH = None
TEAM_ID = None
BUNDLE_ID = None
APP_NAME = None

# ==================== ExportOptions.plist 템플릿 함수 ====================
def get_export_options_content():
    """동적으로 ExportOptions.plist 내용 생성"""
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>teamID</key>
	<string>{TEAM_ID}</string>
	<key>uploadBitcode</key>
	<false/>
	<key>uploadSymbols</key>
	<true/>
	<key>compileBitcode</key>
	<false/>
	<key>destination</key>
	<string>export</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>stripSwiftSymbols</key>
	<true/>
</dict>
</plist>'''

# ==================== 유틸리티 함수 ====================
def run_command(command, description="", check=True, use_shell=True):
    """명령어 실행 및 결과 출력"""
    print(f"\n🔄 {description}")
    
    # 명령어가 리스트인지 문자열인지 확인
    if isinstance(command, list):
        print(f"실행 중: {' '.join(command)}")
        use_shell = False
    else:
        print(f"실행 중: {command}")
    
    try:
        result = subprocess.run(command, shell=use_shell, check=check, 
                              capture_output=True, text=True)
        if result.stdout:
            print(f"출력: {result.stdout.strip()}")
        return result
    except subprocess.CalledProcessError as e:
        print(f"❌ 오류 발생: {e}")
        if e.stderr:
            print(f"오류 메시지: {e.stderr.strip()}")
        if check:
            sys.exit(1)
        return e

def safe_path(path):
    """경로에 공백이 있을 경우 따옴표로 감싸기"""
    return f'"{path}"' if ' ' in str(path) else str(path)

def get_app_name_from_pubspec():
    """pubspec.yaml에서 앱 이름 추출"""
    try:
        with open('pubspec.yaml', 'r', encoding='utf-8') as f:
            pubspec = yaml.safe_load(f)
        
        # description이 있으면 사용, 없으면 name 사용
        app_name = pubspec.get('description', pubspec.get('name', 'FlutterApp'))
        
        # description이 따옴표로 둘러싸여 있다면 제거
        if isinstance(app_name, str):
            app_name = app_name.strip('"').strip("'")
        
        return app_name
        
    except Exception as e:
        print(f"⚠️ pubspec.yaml에서 앱 이름을 읽을 수 없습니다: {e}")
        print("기본값 'FlutterApp'을 사용합니다.")
        return "FlutterApp"

def increment_build_number():
    """pubspec.yaml의 빌드 번호를 순수 YAML 방식으로 안전하게 증가"""
    try:
        # YAML 파싱
        with open('pubspec.yaml', 'r', encoding='utf-8') as f:
            pubspec = yaml.safe_load(f)
        
        current_version = pubspec.get('version', '1.0.0+1')
        
        # version 형태: "1.0.0+1"에서 버전과 빌드번호 분리
        if '+' in current_version:
            version_name, build_number = current_version.split('+')
            new_build_number = str(int(build_number) + 1)
        else:
            version_name = current_version
            new_build_number = "2"
        
        new_version = f"{version_name}+{new_build_number}"
        
        # YAML 데이터 구조 업데이트
        pubspec['version'] = new_version
        
        # YAML로 안전하게 저장
        with open('pubspec.yaml', 'w', encoding='utf-8') as f:
            yaml.dump(pubspec, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
        
        print(f"📈 버전 업데이트: {current_version} → {new_version}")
        return new_version
        
    except Exception as e:
        print(f"⚠️ 버전 번호 증가 실패: {e}")
        print("기존 버전을 유지합니다.")
        return None

def parse_arguments():
    """명령줄 인수 파싱"""
    parser = argparse.ArgumentParser(
        description='iOS App Store 배포 자동화 스크립트',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
사용 예시:
  python distribute.py --api-key-id ABC123DEFG --api-issuer-id "12345678-1234-1234-1234-123456789012" --team-id "XXXXXXXXXX" --bundle-id "com.example.app"

필수 정보 확인 방법:
  API Key 정보: https://appstoreconnect.apple.com/access/integrations/api
  Team ID 확인: security find-identity -v -p codesigning
  Bundle ID 확인: Xcode → Runner → Signing & Capabilities
  
참고: 앱 이름은 pubspec.yaml의 description 또는 name에서 자동으로 가져옵니다.
        """
    )
    
    parser.add_argument(
        '--api-key-id',
        required=True,
        help='App Store Connect API Key ID (10자리 영숫자) - 필수'
    )
    
    parser.add_argument(
        '--api-issuer-id', 
        required=True,
        help='App Store Connect API Issuer ID (UUID 형태) - 필수'
    )
    
    parser.add_argument(
        '--team-id',
        required=True,
        help='iOS Distribution 인증서의 Team ID - 필수'
    )
    
    parser.add_argument(
        '--bundle-id',
        required=True,
        help='iOS 앱의 Bundle Identifier - 필수'
    )
    
    return parser.parse_args()

def initialize_config(args):
    """명령줄 인수를 바탕으로 전역 설정 초기화"""
    global API_KEY_ID, API_ISSUER_ID, API_KEY_FILENAME, API_KEY_PATH
    global TEAM_ID, BUNDLE_ID, APP_NAME
    
    # 명령줄 인수 사용 (모든 값이 필수이므로 반드시 존재)
    API_KEY_ID = args.api_key_id
    API_ISSUER_ID = args.api_issuer_id
    TEAM_ID = args.team_id
    BUNDLE_ID = args.bundle_id
    
    # 앱 이름은 pubspec.yaml에서 자동으로 가져오기
    APP_NAME = get_app_name_from_pubspec()
    
    # API Key 파일명 및 경로 설정
    API_KEY_FILENAME = f"AuthKey_{API_KEY_ID}.p8"
    API_KEY_PATH = os.path.join(API_KEY_DIR, API_KEY_FILENAME)
    
    # 입력값 검증
    if len(API_KEY_ID) != 10:
        print("❌ API Key ID는 10자리여야 합니다.")
        sys.exit(1)
    
    if not API_ISSUER_ID.count('-') == 4 or len(API_ISSUER_ID) != 36:
        print("❌ API Issuer ID는 UUID 형태(XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX)여야 합니다.")
        sys.exit(1)
        
    if len(TEAM_ID) != 10:
        print("❌ Team ID는 10자리여야 합니다.")
        sys.exit(1)

def check_prerequisites():
    """사전 조건 확인"""
    print("📋 사전 조건 확인 중...")
    
    # API Key 파일 확인
    if not os.path.exists(API_KEY_FILENAME):
        print(f"❌ API Key 파일을 찾을 수 없습니다: {API_KEY_FILENAME}")
        print("App Store Connect에서 API Key를 다운로드하고 프로젝트 루트에 배치하세요.")
        sys.exit(1)
    
    # Xcode 설치 확인
    result = subprocess.run("which xcodebuild", shell=True, capture_output=True)
    if result.returncode != 0:
        print("❌ Xcode가 설치되지 않았거나 Command Line Tools가 없습니다.")
        sys.exit(1)
    
    # Flutter 설치 확인
    result = subprocess.run("which flutter", shell=True, capture_output=True)
    if result.returncode != 0:
        print("❌ Flutter가 설치되지 않았습니다.")
        sys.exit(1)
    
    print("✅ 모든 사전 조건이 충족되었습니다.")

def setup_api_key():
    """API Key를 올바른 위치에 복사"""
    print(f"\n🔑 API Key 설정 중...")
    
    # 디렉토리 생성
    os.makedirs(API_KEY_DIR, exist_ok=True)
    
    # API Key 파일 복사
    if not os.path.exists(API_KEY_PATH):
        cmd = ["cp", API_KEY_FILENAME, API_KEY_PATH]
        run_command(cmd, f"API Key를 {API_KEY_DIR}로 복사")
    else:
        print(f"✅ API Key가 이미 설정되어 있습니다: {API_KEY_PATH}")

def create_export_options():
    """ExportOptions.plist 파일 생성"""
    print(f"\n📄 ExportOptions.plist 생성 중...")
    
    os.makedirs("ios", exist_ok=True)
    with open(EXPORT_OPTIONS_PATH, 'w', encoding='utf-8') as f:
        f.write(get_export_options_content())
    
    print(f"✅ {EXPORT_OPTIONS_PATH} 파일이 생성되었습니다.")

def flutter_build():
    """Flutter 빌드 프로세스"""
    print("\n🏗️ Flutter 빌드 시작...")
    
    # Flutter clean
    run_command("flutter clean", "Flutter 프로젝트 정리")
    
    # Flutter pub get
    run_command("flutter pub get", "패키지 의존성 설치")
    
    # Build runner (if needed)
    result = run_command("flutter packages pub run build_runner build --delete-conflicting-outputs", 
                        "코드 생성 (build_runner)", check=False)
    
    # Flutter build ios
    run_command("flutter build ios --release", "iOS 릴리즈 빌드")

def create_archive():
    """Xcode 아카이브 생성"""
    print("\n📦 Xcode 아카이브 생성 중...")
    
    # 이전 아카이브 삭제
    if os.path.exists(ARCHIVE_PATH):
        cmd = ["rm", "-rf", ARCHIVE_PATH]
        run_command(cmd, "이전 아카이브 파일 삭제")
    
    # 새 아카이브 생성
    archive_cmd = [
        "xcodebuild",
        "-workspace", WORKSPACE_PATH,
        "-scheme", SCHEME_NAME,
        "-configuration", "Release",
        "-destination", "generic/platform=iOS",
        "archive",
        "-archivePath", ARCHIVE_PATH
    ]
    
    run_command(archive_cmd, "iOS 아카이브 생성")

def export_ipa():
    """IPA 파일 생성"""
    print("\n📱 IPA 파일 생성 중...")
    
    # 이전 IPA 디렉토리 삭제
    if os.path.exists(IPA_OUTPUT_PATH):
        cmd = ["rm", "-rf", IPA_OUTPUT_PATH]
        run_command(cmd, "이전 IPA 파일 삭제")
    
    # IPA 생성
    export_cmd = [
        "xcodebuild", "-exportArchive",
        "-authenticationKeyIssuerID", API_ISSUER_ID,
        "-authenticationKeyID", API_KEY_ID,
        "-authenticationKeyPath", API_KEY_PATH,
        "-archivePath", ARCHIVE_PATH,
        "-exportOptionsPlist", EXPORT_OPTIONS_PATH,
        "-exportPath", IPA_OUTPUT_PATH
    ]
    
    run_command(export_cmd, "IPA 파일 생성")

def upload_to_appstore():
    """App Store Connect에 업로드"""
    print("\n🚀 App Store Connect 업로드 중...")
    
    # 생성된 IPA 파일 찾기
    ipa_files = list(Path(IPA_OUTPUT_PATH).glob("*.ipa"))
    if not ipa_files:
        print("❌ 생성된 IPA 파일을 찾을 수 없습니다.")
        sys.exit(1)
    
    ipa_file = str(ipa_files[0])
    print(f"📱 업로드할 IPA 파일: {ipa_file}")
    
    # App Store Connect 업로드
    upload_cmd = [
        "xcrun", "altool", "--upload-app", "--type", "ios",
        "--file", ipa_file,
        "--apiKey", API_KEY_ID,
        "--apiIssuer", API_ISSUER_ID
    ]
    
    run_command(upload_cmd, "App Store Connect에 업로드")

def main():
    """메인 실행 함수"""
    # 1. 명령줄 인수 파싱
    args = parse_arguments()
    
    # 2. 설정 초기화
    initialize_config(args)
    
    print("🍎 iOS App Store 배포 자동화 스크립트 시작")
    print(f"앱 이름: {APP_NAME}")
    print(f"Bundle ID: {BUNDLE_ID}")
    print(f"Team ID: {TEAM_ID}")
    print(f"API Key ID: {API_KEY_ID}")
    
    try:
        # 3. 빌드 번호 자동 증가
        increment_build_number()
        
        # 4. 사전 조건 확인
        check_prerequisites()
        
        # 5. API Key 설정
        setup_api_key()
        
        # 6. ExportOptions.plist 생성
        create_export_options()
        
        # 7. Flutter 빌드
        flutter_build()
        
        # 8. Xcode 아카이브 생성
        create_archive()
        
        # 9. IPA 생성
        export_ipa()
        
        # 10. App Store Connect 업로드
        upload_to_appstore()
        
        print("\n🎉 배포 완료!")
        print("App Store Connect에서 앱을 확인하고 심사 제출하세요.")
        
    except KeyboardInterrupt:
        print("\n\n❌ 사용자에 의해 중단되었습니다.")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ 예상치 못한 오류 발생: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()