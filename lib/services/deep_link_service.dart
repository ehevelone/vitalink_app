class VitaLinkDeepLink {
  static String? code;
  static String? shareCode;

  /// Assisted-onboarding code from an agent's link
  /// (`vitalink://activate?onboard=CODE`).
  static String? onboardingCode;

  static void setCode(String? value) {
    code = value;
  }

  static void setShareCode(String? value) {
    shareCode = value;
  }

  static void setOnboardingCode(String? value) {
    onboardingCode = value;
  }

  static void clear() {
    code = null;
  }

  static void clearShareCode() {
    shareCode = null;
  }

  static void clearOnboardingCode() {
    onboardingCode = null;
  }
}
