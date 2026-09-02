class NicknameValidation {
  const NicknameValidation._({required this.value, this.error});

  final String value;
  final String? error;

  bool get isValid => error == null;
}

class NicknamePolicy {
  const NicknamePolicy._();

  static const int maxLength = 24;

  static final RegExp _urlPattern = RegExp(
    r'(https?://|www\.|[a-z0-9-]+\.(com|net|org|kr|io)\b)',
    caseSensitive: false,
  );
  static final RegExp _controlPattern = RegExp(r'[\u0000-\u001f\u007f]');
  static final RegExp _blockedWords = RegExp(
    r'(시발|씨발|병신|개새끼|fuck|shit|bitch)',
    caseSensitive: false,
  );

  static NicknameValidation validate(String input) {
    final String normalized = input.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      return const NicknameValidation._(value: '', error: '닉네임을 입력해주세요.');
    }
    if (normalized.runes.length > maxLength) {
      return NicknameValidation._(
        value: normalized,
        error: '닉네임은 $maxLength자 이하로 입력해주세요.',
      );
    }
    if (_controlPattern.hasMatch(normalized) || normalized.contains('\n')) {
      return NicknameValidation._(
        value: normalized,
        error: '줄바꿈이나 제어 문자는 사용할 수 없어요.',
      );
    }
    if (_urlPattern.hasMatch(normalized)) {
      return NicknameValidation._(
        value: normalized,
        error: '웹 주소는 닉네임으로 사용할 수 없어요.',
      );
    }
    if (_blockedWords.hasMatch(normalized)) {
      return NicknameValidation._(
        value: normalized,
        error: '다른 이용자가 불편할 수 있는 표현은 사용할 수 없어요.',
      );
    }
    return NicknameValidation._(value: normalized);
  }
}
