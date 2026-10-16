import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'secure_store.dart';

class DrugProduct {
  const DrugProduct({
    required this.rxcui,
    required this.rxNormName,
    required this.strength,
    required this.form,
    required this.drugType,
    required this.ndc,
    required this.ndcSource,
    this.friendlyDisplayName,
  });

  final String rxcui;
  final String rxNormName;
  final String strength;
  final String form;
  final String drugType;
  final String ndc;
  final String ndcSource;
  final String? friendlyDisplayName;

  String get friendlyName => friendlyDisplayName ?? friendlyDrugName(rxNormName);

  DrugProduct withFriendlyName(String value) => DrugProduct(
        rxcui: rxcui,
        rxNormName: rxNormName,
        strength: strength,
        form: form,
        drugType: drugType,
        ndc: ndc,
        ndcSource: ndcSource,
        friendlyDisplayName: value,
      );

  factory DrugProduct.fromJson(Map<String, dynamic> json) => DrugProduct(
        rxcui: json['rxcui']?.toString() ?? '',
        rxNormName: json['displayName']?.toString() ?? '',
        strength: json['strength']?.toString() ?? '',
        form: json['form']?.toString() ?? '',
        drugType: json['drugType']?.toString() ?? '',
        ndc: json['ndc']?.toString() ?? '',
        ndcSource: json['ndcSource']?.toString() ?? '',
      );
}

class DrugVerificationResult {
  const DrugVerificationResult._(this.status, {this.match, this.error});

  const DrugVerificationResult.sure(DrugProduct product)
      : this._('sure', match: product);
  const DrugVerificationResult.noMatch() : this._('no_match');
  const DrugVerificationResult.unavailable([String? error])
      : this._('unavailable', error: error);

  final String status;
  final DrugProduct? match;
  final String? error;

  bool get isSure => status == 'sure' && match != null;
  bool get isUnavailable => status == 'unavailable';
}

class DrugOptionsResult {
  const DrugOptionsResult.available(this.products)
      : available = true,
        error = null;
  const DrugOptionsResult.unavailable([this.error])
      : available = false,
        products = const [];

  final bool available;
  final List<DrugProduct> products;
  final String? error;
}

class DrugSearchResult {
  const DrugSearchResult.available(this.names)
      : available = true,
        error = null;
  const DrugSearchResult.unavailable([this.error])
      : available = false,
        names = const [];

  final bool available;
  final List<String> names;
  final String? error;
}

abstract class DrugLookupApi {
  Future<DrugVerificationResult> verify({
    required String name,
    required String dose,
    String form = '',
    String ndc = '',
  });

  Future<DrugSearchResult> search(String text);
  Future<DrugOptionsResult> strengths(String drug);
  Future<DrugVerificationResult> select(String rxcui);
}

class DrugLookupService implements DrugLookupApi {
  DrugLookupService({
    http.Client? client,
    SecureStore? store,
    this.timeout = const Duration(seconds: 15),
  })  : _client = client ?? http.Client(),
        _store = store ?? SecureStore();

  static final Uri _endpoint = Uri.parse(
    'https://vitalink-app.netlify.app/.netlify/functions/drug_lookup',
  );

  final http.Client _client;
  final SecureStore _store;
  final Duration timeout;

  Future<Map<String, dynamic>?> _request(Map<String, dynamic> body) async {
    try {
      final userId = (await _store.getString('userId') ?? '').trim();
      final token = (await _store.getString('userSessionToken') ?? '').trim();
      if (userId.isEmpty || token.isEmpty) return null;
      final response = await _client
          .post(
            _endpoint,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              ...body,
              'userId': userId,
              'sessionToken': token,
            }),
          )
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['success'] != true) return null;
      return Map<String, dynamic>.from(decoded);
    } on TimeoutException {
      return null;
    } on FormatException {
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<DrugVerificationResult> verify({
    required String name,
    required String dose,
    String form = '',
    String ndc = '',
  }) async {
    final response = await _request({
      'action': 'verify',
      'name': name,
      'dose': dose,
      'form': form,
      'ndc': ndc,
    });
    if (response == null) {
      return const DrugVerificationResult.unavailable('service_unavailable');
    }
    if (response['status'] != 'sure' || response['match'] is! Map) {
      return const DrugVerificationResult.noMatch();
    }
    return DrugVerificationResult.sure(
      DrugProduct.fromJson(Map<String, dynamic>.from(response['match'] as Map)),
    );
  }

  @override
  Future<DrugSearchResult> search(String text) async {
    final response = await _request({'action': 'search', 'text': text});
    if (response == null) {
      return const DrugSearchResult.unavailable('service_unavailable');
    }
    final names = (response['results'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => item['name']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
    return DrugSearchResult.available(names);
  }

  @override
  Future<DrugOptionsResult> strengths(String drug) =>
      _productOptions({'action': 'strengths', 'drug': drug});

  @override
  Future<DrugVerificationResult> select(String rxcui) async {
    final response = await _request({'action': 'select', 'rxcui': rxcui});
    if (response == null) {
      return const DrugVerificationResult.unavailable('service_unavailable');
    }
    if (response['result'] is! Map) {
      return const DrugVerificationResult.noMatch();
    }
    return DrugVerificationResult.sure(
      DrugProduct.fromJson(Map<String, dynamic>.from(response['result'] as Map)),
    );
  }

  Future<DrugOptionsResult> _productOptions(Map<String, dynamic> body) async {
    final response = await _request(body);
    if (response == null) {
      return const DrugOptionsResult.unavailable('service_unavailable');
    }
    final products = (response['results'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => DrugProduct.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.rxcui.isNotEmpty && item.rxNormName.isNotEmpty)
        .toList();
    return DrugOptionsResult.available(mergeFriendlyDrugChoices(products));
  }
}

List<DrugProduct> mergeFriendlyDrugChoices(Iterable<DrugProduct> products) {
  final byRxNormIdentity = <String, DrugProduct>{};
  for (final product in products) {
    byRxNormIdentity.putIfAbsent(
      _rxNormIdentity(product.rxNormName),
      () => product,
    );
  }
  final groups = <String, List<DrugProduct>>{};
  for (final product in byRxNormIdentity.values) {
    groups
        .putIfAbsent(product.friendlyName.toLowerCase(), () => [])
        .add(product);
  }
  return groups.values.expand((group) {
    if (group.length == 1) return group;
    final distinctions = group
        .map((product) => _distinguishingLabel(product.rxNormName))
        .toList();
    final plainCount = distinctions.where((value) => value.isEmpty).length;
    var plainOrdinal = 0;
    return group.map((product) {
      final distinction = _distinguishingLabel(product.rxNormName);
      if (distinction.isEmpty && plainCount == 1) return product;
      if (distinction.isEmpty) {
        plainOrdinal += 1;
        if (plainOrdinal == 1) return product;
      }
      final suffix = distinction.isEmpty ? 'option $plainOrdinal' : distinction;
      return product.withFriendlyName('${product.friendlyName} ($suffix)');
    });
  }).toList();
}

String friendlyDrugName(String rxNormName) {
  var text = rxNormName.trim();
  if (text.isEmpty) return '';

  text = _withoutApplicationNumber(text);
  final brand = RegExp(r'\s*\[([^\]]+)\]\s*$').firstMatch(text)?.group(1);
  text = text.replaceFirst(RegExp(r'\s*\[[^\]]+\]\s*$'), '');
  String? puffs;
  String? penVolume;
  List<String>? doseChoices;
  for (var pass = 0; pass < 8; pass += 1) {
    final before = text;
    text = text.replaceFirst(RegExp(r'^Sensor\s+', caseSensitive: false), '');
    text = text.replaceFirst(
      RegExp(r'^(?:Modified|Osmotic)\s+', caseSensitive: false),
      '',
    );
    text = text.replaceFirst(
      RegExp(r'^\d+\s+HR\s+', caseSensitive: false),
      '',
    );
    final actuation = RegExp(r'^(\d+)\s+ACTUAT\s+', caseSensitive: false)
        .firstMatch(text);
    if (actuation != null) {
      puffs ??= actuation.group(1);
      text = text.substring(actuation.end);
    }
    final volume = RegExp(r'^(\d+(?:\.\d+)?)\s+ML\s+', caseSensitive: false)
        .firstMatch(text);
    if (volume != null) {
      penVolume ??= _trimDecimal(volume.group(1)!);
      text = text.substring(volume.end);
    }
    final dosePrefix = RegExp(
      r'^((?:\d+(?:\.\d+)?\s+(?:MCG|MG|G)(?:\s*,\s*|\s+))+)Dose\s+',
      caseSensitive: false,
    ).firstMatch(text);
    if (dosePrefix != null) {
      doseChoices ??= RegExp(
        r'(\d+(?:\.\d+)?)\s+(MCG|MG|G)',
        caseSensitive: false,
      ).allMatches(dosePrefix.group(1)!).map((match) {
        return '${_trimDecimal(match.group(1)!)} ${match.group(2)!.toLowerCase()}';
      }).toList();
      text = text.substring(dosePrefix.end);
    }
    if (text == before) break;
  }
  final genericIngredients = _ingredientNames(text);
  text = text.replaceAll(
    RegExp(r'\b(?:Extended|Sustained|Controlled) Release\b', caseSensitive: false),
    'ER',
  );
  text = text.replaceAll(
    RegExp(r'\bDelayed Release\b', caseSensitive: false),
    'DR',
  );
  text = text.replaceAll(RegExp(r'\bOral\s+', caseSensitive: false), '');
  text = text.replaceAll(
    RegExp(r'\bMetered Dose Inhaler\b', caseSensitive: false),
    'inhaler',
  );
  text = text.replaceAll(
    RegExp(r'\bDry Powder Inhaler\b', caseSensitive: false),
    'dry powder inhaler',
  );
  text = text.replaceAll(
    RegExp(r'\bPen Injector\b', caseSensitive: false),
    'pen',
  );

  text = text.replaceAllMapped(
    RegExp(r'\b(0\.\d+)\s+MG/ACTUAT\b', caseSensitive: false),
    (match) => '${_mgToMicrograms(match.group(1)!)} mcg/puff',
  );
  text = text.replaceAllMapped(
    RegExp(r'\b(\d+(?:\.\d+)?)\s+MG/ACTUAT\b', caseSensitive: false),
    (match) => '${match.group(1)} mg/puff',
  );
  text = text.replaceAllMapped(
    RegExp(r'\b(0\.\d+)\s+MG\b(?!/)', caseSensitive: false),
    (match) =>
        '${_trimDecimal(match.group(1)!)} mg (${_mgToMicrograms(match.group(1)!)} mcg)',
  );
  text = text.replaceAllMapped(
    RegExp(r'\b(\d+(?:\.\d+)?)\s+(MCG|MG|G|ML|UNT|UNIT|UNITS)\b',
        caseSensitive: false),
    (match) {
      final unit = match.group(2)!.toUpperCase();
      final friendlyUnit = switch (unit) {
        'ML' => 'mL',
        'UNT' || 'UNIT' || 'UNITS' => 'units',
        _ => unit.toLowerCase(),
      };
      return '${_trimDecimal(match.group(1)!)} $friendlyUnit';
    },
  );
  text = text.replaceAll(RegExp(r'\bMEQ\b'), 'mEq');
  text = text.replaceAllMapped(
    RegExp(r'/(ML|MG|MCG|UNT|UNIT|UNITS)\b', caseSensitive: false),
    (match) {
      final unit = match.group(1)!.toUpperCase();
      return unit == 'ML' ? '/mL' : '/${unit.toLowerCase()}';
    },
  );
  for (final form in const [
    'Tablet',
    'Capsule',
    'Solution',
    'Suspension',
    'Injection',
    'Cream',
    'Ointment',
    'Patch',
    'Spray',
    'Powder',
  ]) {
    text = text.replaceAll(RegExp('\\b$form\\b'), form.toLowerCase());
  }
  text = text.replaceAllMapped(
    RegExp(r'\b(\d+(?:\.\d+)?\s+(?:mcg|mg|g|ml|mEq|unt|unit|units)(?:/[^ ]+)?)\s+(ER|DR)\b'),
    (match) => '${match.group(2)} ${match.group(1)}',
  );
  text = text
      .toLowerCase()
      .replaceAll(RegExp(r'\ber\b'), 'ER')
      .replaceAll(RegExp(r'\bdr\b'), 'DR')
      .replaceAll(RegExp(r'\bmeq\b'), 'mEq')
      .replaceAll(RegExp(r'\bml\b'), 'mL')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  final generic = text.isEmpty
      ? ''
      : '${text[0].toUpperCase()}${text.substring(1)}';
  var branded = brand == null || brand.trim().isEmpty
      ? generic
      : '${brand.trim()} ($genericIngredients)${_brandDetails(generic, genericIngredients)}';
  if (doseChoices != null && doseChoices.isNotEmpty) {
    final productName = brand == null || brand.trim().isEmpty
        ? _capitalize(genericIngredients)
        : '${brand.trim()} ($genericIngredients)';
    branded = '$productName pen, ${doseChoices.join(' or ')} dose';
  }
  final package = [
    if (puffs != null) '$puffs puffs',
    if (penVolume != null) '$penVolume mL',
  ];
  return package.isEmpty ? branded : '$branded (${package.join(', ')})';
}

String _capitalize(String value) => value.isEmpty
    ? ''
    : '${value[0].toUpperCase()}${value.substring(1)}';

String _withoutApplicationNumber(String value) => value.replaceFirst(
      RegExp(r'^(?:NDA|ANDA|BLA)\s*-?\s*\d+\s+', caseSensitive: false),
      '',
    );

String _rxNormIdentity(String value) => _withoutApplicationNumber(value)
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();

String _distinguishingLabel(String value) {
  final lower = _withoutApplicationNumber(value).toLowerCase();
  if (lower.startsWith('osmotic ')) return 'osmotic';
  if (lower.startsWith('modified ')) return 'modified-release';
  if (lower.startsWith('sensor ')) return 'sensor';
  return '';
}

String _ingredientNames(String value) {
  return value.split(' / ').map((part) {
    return part
        .replaceFirst(RegExp(r'\s+\d.*$'), '')
        .trim()
        .toLowerCase();
  }).where((part) => part.isNotEmpty).join(' / ');
}

String _brandDetails(String value, String ingredients) {
  var details = value;
  final names = ingredients.split(' / ');
  for (var index = 0; index < names.length; index += 1) {
    final escaped = RegExp.escape(names[index]);
    details = index == 0
        ? details.replaceFirst(
            RegExp('^$escaped\\s+', caseSensitive: false),
            ' ',
          )
        : details.replaceFirst(
            RegExp(' / $escaped\\s+', caseSensitive: false),
            ' / ',
          );
  }
  return details;
}

String _trimDecimal(String value) {
  if (!value.contains('.')) return value;
  return value.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

String _mgToMicrograms(String milligrams) {
  final parts = milligrams.split('.');
  final whole = parts.first;
  final fraction = parts.length == 1 ? '' : parts[1];
  final digits = BigInt.parse('$whole$fraction');
  final scale = fraction.length;
  if (scale <= 3) {
    return (digits * BigInt.from(10).pow(3 - scale)).toString();
  }
  final decimalPlaces = scale - 3;
  final raw = digits.toString().padLeft(decimalPlaces + 1, '0');
  final split = raw.length - decimalPlaces;
  return _trimDecimal('${raw.substring(0, split)}.${raw.substring(split)}');
}
