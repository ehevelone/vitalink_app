class VitaLinkRegistrationLink {
  final String code;
  final String route;

  const VitaLinkRegistrationLink(this.code, this.route);

  static VitaLinkRegistrationLink? fromUri(Uri uri) {
    if (uri.scheme != 'vitalink' ||
        !const {'activate', 'register', 'agent'}.contains(uri.host)) {
      return null;
    }

    final queryCode = uri.queryParameters['code'];
    final legacyCode = uri.host == 'activate' && uri.pathSegments.isNotEmpty
        ? uri.pathSegments.first
        : null;
    final code = (queryCode ?? legacyCode ?? '').trim().toUpperCase();
    if (code.isEmpty || !RegExp(r'^[A-Z0-9-]{1,64}$').hasMatch(code)) {
      return null;
    }

    final kind = uri.queryParameters['kind']?.toLowerCase();
    final isAgent = kind == 'agent' ||
        (kind == null && const {'register', 'agent'}.contains(uri.host));
    return VitaLinkRegistrationLink(
      code,
      isAgent ? '/terms_agent' : '/terms_user',
    );
  }
}

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
