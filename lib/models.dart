// =========================
// Medication Model
// =========================
class Medication {
  String name;
  String dose;
  String frequency;
  String prescriber;
  String source;
  DateTime updatedAt;

  Medication({
    this.name = '',
    this.dose = '',
    this.frequency = '',
    this.prescriber = '',
    this.source = 'Manual',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'name': name,
        'dose': dose,
        'frequency': frequency,
        'prescriber': prescriber,
        'source': source,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Medication.fromJson(Map<String, dynamic> json) => Medication(
        name: json['name'] ?? '',
        dose: json['dose'] ?? '',
        frequency: json['frequency'] ?? '',
        prescriber: json['prescriber'] ?? '',
        source: json['source'] ?? 'Manual',
        updatedAt:
            DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
      );
}

// =========================
// Doctor Model
// =========================
class Doctor {
  String name;
  String specialty;
  String clinic;
  String phone;

  Doctor({
    this.name = '',
    this.specialty = '',
    this.clinic = '',
    this.phone = '',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'specialty': specialty,
        'clinic': clinic,
        'phone': phone,
      };

  factory Doctor.fromJson(Map<String, dynamic> json) => Doctor(
        name: json['name'] ?? '',
        specialty: json['specialty'] ?? '',
        clinic: json['clinic'] ?? '',
        phone: json['phone'] ?? '',
      );
}

// =========================
// Insurance Card Model
// =========================
class InsuranceCard {
  String id;
  String carrier;
  String policy;
  String memberId;
  String policyType;
  String frontImagePath;
  String? backImagePath;
  String? imagePath;
  String source;
  DateTime updatedAt;

  InsuranceCard({
    String? id,
    this.carrier = '',
    this.policy = '',
    this.memberId = '',
    this.policyType = '',
    required this.frontImagePath,
    this.backImagePath,
    this.imagePath,
    this.source = 'Manual',
    DateTime? updatedAt,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'carrier': carrier,
        'policy': policy,
        'memberId': memberId,
        'policyType': policyType,
        'frontImagePath': frontImagePath,
        'backImagePath': backImagePath,
        'imagePath': imagePath ?? frontImagePath,
        'source': source,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory InsuranceCard.fromJson(Map<String, dynamic> json) => InsuranceCard(
        id: json['id'],
        carrier: json['carrier'] ?? '',
        policy: json['policy'] ?? '',
        memberId: json['memberId'] ?? '',
        policyType: json['policyType'] ?? '',
        frontImagePath: json['frontImagePath'] ?? '',
        backImagePath: json['backImagePath'],
        imagePath: json['imagePath'],
        source: json['source'] ?? 'Manual',
        updatedAt:
            DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
      );
}

// =========================
// Insurance Model
// =========================
class Insurance {
  String carrier;
  String policy;
  String memberId;
  String group;
  String phone;
  String policyType;
  List<String> decPagePaths;
  List<String> benefits;
  List<InsuranceCard> cards;

  Insurance({
    this.carrier = '',
    this.policy = '',
    this.memberId = '',
    this.group = '',
    this.phone = '',
    this.policyType = '',
    List<String>? decPagePaths,
    List<String>? benefits,
    List<InsuranceCard>? cards,
  })  : decPagePaths = decPagePaths ?? [],
        benefits = benefits ?? [],
        cards = cards ?? [];

  Map<String, dynamic> toJson() => {
        'carrier': carrier,
        'policy': policy,
        'memberId': memberId,
        'group': group,
        'phone': phone,
        'policyType': policyType,
        'decPagePaths': decPagePaths,
        'benefits': benefits,
        'cards': cards.map((c) => c.toJson()).toList(),
      };

  factory Insurance.fromJson(Map<String, dynamic> json) => Insurance(
        carrier: json['carrier'] ?? '',
        policy: json['policy'] ?? '',
        memberId: json['memberId'] ?? '',
        group: json['group'] ?? '',
        phone: json['phone'] ?? '',
        policyType: json['policyType'] ?? '',
        decPagePaths:
            (json['decPagePaths'] as List<dynamic>? ?? []).cast<String>(),
        benefits:
            (json['benefits'] as List<dynamic>? ?? []).cast<String>(),
        cards: (json['cards'] as List<dynamic>? ?? [])
            .map((c) => InsuranceCard.fromJson(c))
            .toList(),
      );
}

// =========================
// Emergency Info Model
// =========================
class EmergencyInfo {
  String contact;
  String phone;
  String allergies;
  String conditions;
  String bloodType;
  bool organDonor;

  EmergencyInfo({
    this.contact = '',
    this.phone = '',
    this.allergies = '',
    this.conditions = '',
    this.bloodType = '',
    this.organDonor = false,
  });

  EmergencyInfo copyWith({
    String? contact,
    String? phone,
    String? allergies,
    String? conditions,
    String? bloodType,
    bool? organDonor,
  }) {
    return EmergencyInfo(
      contact: contact ?? this.contact,
      phone: phone ?? this.phone,
      allergies: allergies ?? this.allergies,
      conditions: conditions ?? this.conditions,
      bloodType: bloodType ?? this.bloodType,
      organDonor: organDonor ?? this.organDonor,
    );
  }

  Map<String, dynamic> toJson() => {
        'contact': contact,
        'phone': phone,
        'allergies': allergies,
        'conditions': conditions,
        'bloodType': bloodType,
        'organDonor': organDonor,
      };

  factory EmergencyInfo.fromJson(Map<String, dynamic> json) =>
      EmergencyInfo(
        contact: json['contact'] ?? '',
        phone: json['phone'] ?? '',
        allergies: json['allergies'] ?? '',
        conditions: json['conditions'] ?? '',
        bloodType: json['bloodType'] ?? '',
        organDonor: json['organDonor'] ?? false,
      );
}

// =========================
// Profile Model (LAST)
// =========================
class Profile {
  String fullName;
  String? dob;
  DateTime updatedAt;
  String userPhone;

  List<Medication> meds;
  List<Doctor> doctors;
  List<Insurance> insurances;
  List<InsuranceCard> orphanCards;
  EmergencyInfo emergency;

  String? username;
  String? password;
  bool useBiometrics;
  bool acceptedTerms;
  bool registered;

  bool agentTerms;
  bool agentRegistered;
  bool agentLoggedIn;
  bool agentSetupDone;

  int? agentId;
  String? agentName;
  String? agentEmail;
  String? agentPhone;
  String? agentNpn;

  Profile({
    this.fullName = '',
    this.dob,
    DateTime? updatedAt,
    this.userPhone = '',
    List<Medication>? meds,
    List<Doctor>? doctors,
    List<Insurance>? insurances,
    List<InsuranceCard>? orphanCards,
    EmergencyInfo? emergency,
    this.username,
    this.password,
    this.useBiometrics = false,
    this.acceptedTerms = false,
    this.registered = false,
    this.agentTerms = false,
    this.agentRegistered = false,
    this.agentLoggedIn = false,
    this.agentSetupDone = false,
    this.agentId,
    this.agentName,
    this.agentEmail,
    this.agentPhone,
    this.agentNpn,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        meds = meds ?? [],
        doctors = doctors ?? [],
        insurances = insurances ?? [],
        orphanCards = orphanCards ?? [],
        emergency = emergency ?? EmergencyInfo();

  Profile copyWith({
    String? fullName,
    String? dob,
    DateTime? updatedAt,
    String? userPhone,
    List<Medication>? meds,
    List<Doctor>? doctors,
    List<Insurance>? insurances,
    List<InsuranceCard>? orphanCards,
    EmergencyInfo? emergency,
    String? username,
    String? password,
    bool? useBiometrics,
    bool? acceptedTerms,
    bool? registered,
    bool? agentTerms,
    bool? agentRegistered,
    bool? agentLoggedIn,
    bool? agentSetupDone,
    int? agentId,
    String? agentName,
    String? agentEmail,
    String? agentPhone,
    String? agentNpn,
  }) {
    return Profile(
      fullName: fullName ?? this.fullName,
      dob: dob ?? this.dob,
      updatedAt: updatedAt ?? this.updatedAt,
      userPhone: userPhone ?? this.userPhone,
      meds: meds ?? this.meds,
      doctors: doctors ?? this.doctors,
      insurances: insurances ?? this.insurances,
      orphanCards: orphanCards ?? this.orphanCards,
      emergency: emergency ?? this.emergency,
      username: username ?? this.username,
      password: password ?? this.password,
      useBiometrics: useBiometrics ?? this.useBiometrics,
      acceptedTerms: acceptedTerms ?? this.acceptedTerms,
      registered: registered ?? this.registered,
      agentTerms: agentTerms ?? this.agentTerms,
      agentRegistered: agentRegistered ?? this.agentRegistered,
      agentLoggedIn: agentLoggedIn ?? this.agentLoggedIn,
      agentSetupDone: agentSetupDone ?? this.agentSetupDone,
      agentId: agentId ?? this.agentId,
      agentName: agentName ?? this.agentName,
      agentEmail: agentEmail ?? this.agentEmail,
      agentPhone: agentPhone ?? this.agentPhone,
      agentNpn: agentNpn ?? this.agentNpn,
    );
  }

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        fullName: json['fullName'] ?? '',
        dob: json['dob'],
        updatedAt:
            DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
        userPhone: json['userPhone'] ?? '',
        meds: (json['meds'] as List<dynamic>? ?? [])
            .map((m) => Medication.fromJson(m))
            .toList(),
        doctors: (json['doctors'] as List<dynamic>? ?? [])
            .map((d) => Doctor.fromJson(d))
            .toList(),
        insurances: (json['insurances'] as List<dynamic>? ?? [])
            .map((i) => Insurance.fromJson(i))
            .toList(),
        orphanCards: (json['orphanCards'] as List<dynamic>? ?? [])
            .map((c) => InsuranceCard.fromJson(c))
            .toList(),
        emergency: json['emergency'] != null
            ? EmergencyInfo.fromJson(json['emergency'])
            : EmergencyInfo(),
        username: json['username'],
        password: json['password'],
        useBiometrics: json['useBiometrics'] ?? false,
        acceptedTerms: json['acceptedTerms'] ?? false,
        registered: json['registered'] ?? false,
        agentTerms: json['agentTerms'] ?? false,
        agentRegistered: json['agentRegistered'] ?? false,
        agentLoggedIn: json['agentLoggedIn'] ?? false,
        agentSetupDone: json['agentSetupDone'] ?? false,
        agentId: json['agentId'],
        agentName: json['agentName'],
        agentEmail: json['agentEmail'],
        agentPhone: json['agentPhone'],
        agentNpn: json['agentNpn'],
      );
}

// =========================
// Profile Helpers
// =========================
extension ProfileHelpers on Profile {
  String get displayName {
    if (fullName.isNotEmpty) return fullName;

    final safeAgentName = agentName ?? '';
    if (safeAgentName.isNotEmpty) return safeAgentName;

    return "User";
  }
}