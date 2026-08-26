import 'package:uuid/uuid.dart';

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
// Appointment Model
// =========================
class UserAppointment {
  String doctorName;
  String specialty;
  DateTime appointmentAt;
  String notes;
  DateTime updatedAt;

  UserAppointment({
    this.doctorName = '',
    this.specialty = '',
    DateTime? appointmentAt,
    this.notes = '',
    DateTime? updatedAt,
  })  : appointmentAt = appointmentAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'doctorName': doctorName,
        'specialty': specialty,
        'appointmentAt': appointmentAt.toIso8601String(),
        'notes': notes,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory UserAppointment.fromJson(Map<String, dynamic> json) =>
      UserAppointment(
        doctorName: json['doctorName'] ?? '',
        specialty: json['specialty'] ?? '',
        appointmentAt:
            DateTime.tryParse(json['appointmentAt'] ?? '') ?? DateTime.now(),
        notes: json['notes'] ?? '',
        updatedAt:
            DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
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
  String medicarePlanId;
  String medicarePlanKind;
  String ocrText;
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
    this.medicarePlanId = '',
    this.medicarePlanKind = '',
    this.ocrText = '',
    required this.frontImagePath,
    this.backImagePath,
    this.imagePath,
    this.source = 'Manual',
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'carrier': carrier,
        'policy': policy,
        'memberId': memberId,
        'policyType': policyType,
        'medicarePlanId': medicarePlanId,
        'medicarePlanKind': medicarePlanKind,
        'ocrText': ocrText,
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
        medicarePlanId: json['medicarePlanId'] ?? '',
        medicarePlanKind: json['medicarePlanKind'] ?? '',
        ocrText: json['ocrText'] ?? '',
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

  String insuredName;
  String beneficiary;

  List<String> decPagePaths;
  List<Map<String, String>> benefits;
  List<InsuranceCard> cards;

  Insurance({
    this.carrier = '',
    this.policy = '',
    this.memberId = '',
    this.group = '',
    this.phone = '',
    this.policyType = '',
    this.insuredName = '',
    this.beneficiary = '',
    List<String>? decPagePaths,
    List<Map<String, String>>? benefits,
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
        'insuredName': insuredName,
        'beneficiary': beneficiary,
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
        insuredName: json['insuredName'] ?? '',
        beneficiary: json['beneficiary'] ?? '',
        decPagePaths:
            (json['decPagePaths'] as List<dynamic>? ?? []).cast<String>(),
        benefits: (json['benefits'] as List<dynamic>? ?? [])
            .map((b) {
              if (b is Map) {
                return {
                  'name': b['name']?.toString() ?? '',
                  'value': b['value']?.toString() ?? '',
                };
              } else {
                return {
                  'name': b.toString(),
                  'value': '',
                };
              }
            })
            .toList(),
        cards: (json['cards'] as List<dynamic>? ?? [])
            .map((c) => InsuranceCard.fromJson(c))
            .toList(),
      );
}

// =========================
// Emergency Contact Model
// =========================
class EmergencyContact {
  String name;
  String phone;

  EmergencyContact({
    this.name = '',
    this.phone = '',
  });

  bool get hasDetails => name.trim().isNotEmpty || phone.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
      };

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      EmergencyContact(
        name: json['name'] ?? json['contact'] ?? '',
        phone: json['phone'] ?? '',
      );
}

// =========================
// Emergency Info Model
// =========================
class EmergencyInfo {
  String contact;
  String phone;
  List<EmergencyContact> contacts;
  String allergies;
  String conditions;
  String bloodType;
  String implants;
  String procedures;
  bool organDonor;

  EmergencyInfo({
    this.contact = '',
    this.phone = '',
    List<EmergencyContact>? contacts,
    this.allergies = '',
    this.conditions = '',
    this.bloodType = '',
    this.implants = '',
    this.procedures = '',
    this.organDonor = false,
  }) : contacts = contacts ?? [];

  List<EmergencyContact> get effectiveContacts {
    final saved = contacts.where((c) => c.hasDetails).toList();
    if (saved.isNotEmpty) return saved;

    final legacy = EmergencyContact(name: contact, phone: phone);
    return legacy.hasDetails ? [legacy] : [];
  }

  EmergencyInfo copyWith({
    String? contact,
    String? phone,
    List<EmergencyContact>? contacts,
    String? allergies,
    String? conditions,
    String? bloodType,
    String? implants,
    String? procedures,
    bool? organDonor,
  }) {
    return EmergencyInfo(
      contact: contact ?? this.contact,
      phone: phone ?? this.phone,
      contacts: contacts ?? this.contacts,
      allergies: allergies ?? this.allergies,
      conditions: conditions ?? this.conditions,
      bloodType: bloodType ?? this.bloodType,
      implants: implants ?? this.implants,
      procedures: procedures ?? this.procedures,
      organDonor: organDonor ?? this.organDonor,
    );
  }

  Map<String, dynamic> toJson() => {
        'contact': contact,
        'phone': phone,
        'contacts': effectiveContacts.map((c) => c.toJson()).toList(),
        'allergies': allergies,
        'conditions': conditions,
        'bloodType': bloodType,
        'implants': implants,
        'procedures': procedures,
        'organDonor': organDonor,
      };

  factory EmergencyInfo.fromJson(Map<String, dynamic> json) {
    final parsedContacts = (json['contacts'] as List<dynamic>? ??
            json['emergencyContacts'] as List<dynamic>? ??
            [])
        .whereType<Map>()
        .map((c) => EmergencyContact.fromJson(Map<String, dynamic>.from(c)))
        .where((c) => c.hasDetails)
        .toList();

    final legacyContact = json['contact'] ?? '';
    final legacyPhone = json['phone'] ?? '';
    final firstContact =
        parsedContacts.isNotEmpty ? parsedContacts.first.name : legacyContact;
    final firstPhone =
        parsedContacts.isNotEmpty ? parsedContacts.first.phone : legacyPhone;

    return EmergencyInfo(
        contact: firstContact,
        phone: firstPhone,
        contacts: parsedContacts,
        allergies: json['allergies'] ?? '',
        conditions: json['conditions'] ?? '',
        bloodType: json['bloodType'] ?? '',
        implants: json['implants'] ?? '',
        procedures: json['procedures'] ?? '',
        organDonor: json['organDonor'] ?? false,
      );
  }
}

// =========================
// Profile Model
// =========================
class Profile {
  String id;

  String fullName;
  String? dob;
  DateTime updatedAt;
  String userPhone;
  String? address;
  String? city;
  String? state;
  String? zip;

  List<Medication> meds;
  List<Doctor> doctors;
  List<UserAppointment> appointments;
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

  String? qrToken; // ✅ ADDED

  Profile({
    String? id,
    this.fullName = '',
    this.dob,
    DateTime? updatedAt,
    this.userPhone = '',
    this.address,
    this.city,
    this.state,
    this.zip,
    List<Medication>? meds,
    List<Doctor>? doctors,
    List<UserAppointment>? appointments,
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
    this.qrToken, // ✅ ADDED
  })  : id = id ?? const Uuid().v4(),
        updatedAt = updatedAt ?? DateTime.now(),
        meds = meds ?? [],
        doctors = doctors ?? [],
        appointments = appointments ?? [],
        insurances = insurances ?? [],
        orphanCards = orphanCards ?? [],
        emergency = emergency ?? EmergencyInfo();

  Profile copyWith({
    String? id,
    String? fullName,
    String? dob,
    DateTime? updatedAt,
    String? userPhone,
    String? address,
    String? city,
    String? state,
    String? zip,
    List<Medication>? meds,
    List<Doctor>? doctors,
    List<UserAppointment>? appointments,
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
    String? qrToken,
  }) {
    return Profile(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      dob: dob ?? this.dob,
      updatedAt: updatedAt ?? this.updatedAt,
      userPhone: userPhone ?? this.userPhone,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      zip: zip ?? this.zip,
      meds: meds ?? this.meds,
      doctors: doctors ?? this.doctors,
      appointments: appointments ?? this.appointments,
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
      qrToken: qrToken ?? this.qrToken,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fullName': fullName,
        'dob': dob,
        'updatedAt': updatedAt.toIso8601String(),
        'userPhone': userPhone,
        'address': address,
        'city': city,
        'state': state,
        'zip': zip,
        'meds': meds.map((m) => m.toJson()).toList(),
        'doctors': doctors.map((d) => d.toJson()).toList(),
        'appointments': appointments.map((a) => a.toJson()).toList(),
        'insurances': insurances.map((i) => i.toJson()).toList(),
        'orphanCards': orphanCards.map((c) => c.toJson()).toList(),
        'emergency': emergency.toJson(),
        'username': username,
        'password': password,
        'useBiometrics': useBiometrics,
        'acceptedTerms': acceptedTerms,
        'registered': registered,
        'agentTerms': agentTerms,
        'agentRegistered': agentRegistered,
        'agentLoggedIn': agentLoggedIn,
        'agentSetupDone': agentSetupDone,
        'agentId': agentId,
        'agentName': agentName,
        'agentEmail': agentEmail,
        'agentPhone': agentPhone,
        'agentNpn': agentNpn,
        'qr_Token': qrToken,
      };

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'],
        fullName: json['fullName'] ?? '',
        dob: json['dob'],
        updatedAt:
            DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
        userPhone: json['userPhone'] ?? '',
        address: json['address'],
        city: json['city'],
        state: json['state'],
        zip: json['zip'],
        meds: (json['meds'] as List<dynamic>? ?? [])
            .map((m) => Medication.fromJson(m))
            .toList(),
        doctors: (json['doctors'] as List<dynamic>? ?? [])
            .map((d) => Doctor.fromJson(d))
            .toList(),
        appointments: (json['appointments'] as List<dynamic>? ?? [])
            .map((a) => UserAppointment.fromJson(a))
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
        qrToken: json['qr_token'],
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
