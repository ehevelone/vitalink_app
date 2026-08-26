class VitaLinkDeepLink {
  static String? code;
  static String? shareCode;

  static void setCode(String? value) {
    code = value;
  }

  static void setShareCode(String? value) {
    shareCode = value;
  }

  static void clear() {
    code = null;
  }

  static void clearShareCode() {
    shareCode = null;
  }
}
