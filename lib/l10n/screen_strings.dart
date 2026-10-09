// Spanish/English wording for screens added to the app after app_strings.dart.
// Use like the getters in AppStrings: AppStrings.of(context).medsTitle.
// Generated sections are maintained per screen area; keep English text
// identical to what the screens showed before translation.
import 'app_strings.dart';

extension ScreenStrings on AppStrings {
  bool get _isEs => languageCode == 'es';

  // ---- hand-written (wording depends on grammar, not a simple swap) ----

  /// itemType is prescription / supplement / otc / unknown.
  String itemTypeNoun(String itemType) {
    switch (itemType) {
      case 'supplement':
        return _isEs ? 'suplemento' : 'Supplement';
      case 'otc':
        return _isEs ? 'producto de venta libre' : 'OTC';
      case 'unknown':
        return _isEs ? 'artículo' : 'Item';
      default:
        return _isEs ? 'medicamento' : 'Medication';
    }
  }

  String alreadySavedTitle(String itemType) => _isEs
      ? 'Este ${itemTypeNoun(itemType)} ya está guardado'
      : 'This ${itemTypeNoun(itemType)} Is Already Saved';

  String updateThisItem(String itemType) => _isEs
      ? 'Actualizar este ${itemTypeNoun(itemType)}'
      : 'Update This ${itemTypeNoun(itemType)}';

  /// item is 'pharmacy' or 'doctor'.
  String couldNotCheck(String item) => _isEs
      ? 'No se pudo verificar ${item == 'doctor' ? 'el médico' : 'la farmacia'}'
      : 'Could not check $item';

  /// Doctor specialties are stored in English (the NPI lookup matches on
  /// them); this is only the label shown to the user. Unknown values, such
  /// as registry taxonomy names, are shown as stored.
  String doctorSpecialtyLabel(String value) {
    if (!_isEs) return value;
    const es = {
      'Primary': 'Atención primaria',
      'Primary Care': 'Atención primaria',
      'Cardiologist': 'Cardiólogo',
      'Orthopedic': 'Ortopedista',
      'Neurologist': 'Neurólogo',
      'Endocrinologist': 'Endocrinólogo',
      'Pulmonologist': 'Neumólogo',
      'Gastroenterologist': 'Gastroenterólogo',
      'Nephrologist': 'Nefrólogo',
      'Urologist': 'Urólogo',
      'Oncologist': 'Oncólogo',
      'Dermatologist': 'Dermatólogo',
      'Psychiatrist': 'Psiquiatra',
      'Psychologist / Clinical Psychologist': 'Psicólogo / psicólogo clínico',
      'Clinical Social Worker': 'Trabajador social clínico',
      'Professional Counselor': 'Consejero profesional',
      'Mental Health Counselor': 'Consejero de salud mental',
      'Marriage & Family Therapist': 'Terapeuta matrimonial y familiar',
      'Psychiatric Nurse Practitioner': 'Enfermero practicante psiquiátrico',
      'Addiction Counselor': 'Consejero en adicciones',
      'Pain Management': 'Manejo del dolor',
      'Other': 'Otro',
    };
    return es[value.trim()] ?? value;
  }

  /// How a card or medication was added. Stored in English ("Manual",
  /// "Scan", "Scan + AI", "Scanned"); only the shown label is translated.
  String sourceLabel(String source) {
    if (!_isEs) return source;
    const es = {
      'Manual': 'Manual',
      'Scan': 'Escaneo',
      'Scan + AI': 'Escaneo + IA',
      'Scanned': 'Escaneado',
      'Scanned medication list': 'Lista de medicamentos escaneada',
    };
    return es[source.trim()] ?? source;
  }

  String sourceValue(String source) => _isEs
      ? 'Origen: ${sourceLabel(source)}'
      : 'Source: ${sourceLabel(source)}';

  String get agentWord => _isEs ? 'Agente' : 'Agent';

  // ---- Service messages (shown through AppStrings.current()) ----
  String serverReturned(Object status) => _isEs
      ? 'El servidor respondió con el código $status'
      : 'Server returned $status';
  String get requestTimedOut =>
      _isEs ? 'La solicitud tardó demasiado' : 'Request timed out';
  String get invalidCredentials =>
      _isEs ? 'Credenciales no válidas' : 'Invalid credentials';
  String get userDataMissing =>
      _isEs ? 'Faltan los datos del usuario' : 'User data missing';
  String get invalidUserSession =>
      _isEs ? 'Sesión de usuario no válida' : 'Invalid user session';
  String get invalidAgentCode =>
      _isEs ? 'Código de agente no válido' : 'Invalid agent code';
  String get unableToCreateTransfer =>
      _isEs ? 'No se pudo crear el traslado.' : 'Unable to create transfer.';
  String get unableToCreateTransferCode => _isEs
      ? 'No se pudo crear el código de traslado.'
      : 'Unable to create transfer code.';
  String get unableToUploadTransfer => _isEs
      ? 'No se pudieron subir los datos del traslado.'
      : 'Unable to upload transfer data.';
  String get unableToCheckTransfer => _isEs
      ? 'No se pudo verificar el estado del traslado.'
      : 'Unable to check transfer status.';
  String get unableToLoadTransfer =>
      _isEs ? 'No se pudo cargar el traslado.' : 'Unable to load transfer.';
  String get transferPackageNotAvailable => _isEs
      ? 'Este paquete de traslado no está disponible.'
      : 'This transfer package is not available.';
  String get unableToDownloadTransfer => _isEs
      ? 'No se pudieron descargar los datos del traslado.'
      : 'Unable to download transfer data.';
  String get transferCleanupFailed => _isEs
      ? 'No se pudo completar la limpieza del traslado.'
      : 'Transfer cleanup failed.';
  String get logInBeforeMoving => _isEs
      ? 'Inicie sesión antes de mover VitaLink a un dispositivo nuevo.'
      : 'Please log in before moving VitaLink to a new device.';
  String get noProfilesInTransfer => _isEs
      ? 'No se encontraron perfiles de VitaLink en este traslado.'
      : 'No VitaLink profiles were found in this transfer.';
  String get enterCompleteCode =>
      _isEs ? 'Ingrese el código completo.' : 'Enter the complete code.';
  String get unsupportedSharePackage => _isEs
      ? 'Paquete de perfil compartido no compatible.'
      : 'Unsupported shared profile package.';
  String get invalidShareKey =>
      _isEs ? 'Clave para compartir no válida.' : 'Invalid share key.';
  String get providerLookupFailed =>
      _isEs ? 'No se pudo buscar al proveedor' : 'Provider lookup failed';
  String get updateAvailableTitle => _isEs
      ? 'Hay una actualización de VitaLink disponible'
      : 'VitaLink Update Available';
  String get updateAvailableMessage => _isEs
      ? 'Hay una versión más reciente de VitaLink. Actualice para obtener las correcciones y mejoras más recientes.'
      : 'A newer version of VitaLink is available. Please update for the latest fixes and improvements.';

  // Referral relationships stay English when sent to the server.
  String relationshipLabel(String value) {
    if (!_isEs) return value;
    const es = {
      'Friend': 'Amigo',
      'Coworker': 'Compañero de trabajo',
      'Neighbor': 'Vecino',
      'Relative': 'Familiar',
      'Other': 'Otro',
    };
    return es[value] ?? value;
  }

  String get relationshipWord => _isEs ? 'Parentesco' : 'Relationship';

  // Referral statuses stay English when sent to the server and CRM.
  String referralStatusLabel(String status) {
    if (!_isEs) return status;
    const es = {
      'Introduction Sent': 'Presentación enviada',
      'Referral Link Opened': 'Enlace de referido abierto',
      'Contact Preference Submitted': 'Preferencia de contacto enviada',
      'Agent Contacted': 'Agente se comunicó',
      'Appointment Scheduled': 'Cita programada',
      'Client Added': 'Cliente agregado',
      'Closed': 'Cerrado',
    };
    return es[status] ?? status;
  }

  // Prospect topics come from server templates in English.
  String prospectTopicLabel(String topic) {
    if (!_isEs) return topic;
    switch (topic.trim().toLowerCase()) {
      case 'medicare':
        return 'Medicare';
      case 'life insurance':
        return 'seguro de vida';
      case 'insurance':
        return 'seguros';
      default:
        return topic;
    }
  }

  // ---- generated: start ----

  // Medications (meds_screen, meds_view)
  String get noLocalPharmacy =>
      _isEs ? 'No, farmacia local' : 'No, local pharmacy';
  String get yesMailOrder =>
      _isEs ? 'Sí, pedido por correo' : 'Yes, mail order';
  String get notSure => _isEs ? 'No estoy seguro' : 'Not sure';
  String get sessionNotVerifiedRetry => _isEs
      ? 'VitaLink no pudo verificar su sesión. Inicie sesión de nuevo y vuelva a intentarlo.'
      : 'VitaLink could not verify your signed-in session. Please sign in again, then retry.';
  String get providerSearchUnreachable => _isEs
      ? 'VitaLink no pudo conectarse a la búsqueda de proveedores. Intente de nuevo.'
      : 'VitaLink could not reach the provider search. Please try again.';
  String get addMedicationOrSupplement => _isEs
      ? 'Agregar medicamento o suplemento'
      : 'Add Medication or Supplement';
  String get editMedicationOrSupplement => _isEs
      ? 'Editar medicamento o suplemento'
      : 'Edit Medication or Supplement';
  String get typeLabel => _isEs ? 'Tipo' : 'Type';
  String get typePrescription => _isEs ? 'Con receta' : 'Prescription';
  String get typeSupplement => _isEs ? 'Suplemento' : 'Supplement';
  String get typeOtc => _isEs ? 'De venta libre' : 'OTC';
  String get quantity => _isEs ? 'Cantidad' : 'Quantity';
  String get amountTaken => _isEs ? 'Cantidad que toma' : 'Amount Taken';
  String get doseStrength =>
      _isEs ? 'Dosis / concentración' : 'Dose / Strength';
  String get frequency => _isEs ? 'Frecuencia' : 'Frequency';
  String get servingSize => _isEs ? 'Tamaño de la porción' : 'Serving Size';
  String get pharmacyAndPhone =>
      _isEs ? 'Farmacia (y teléfono)' : 'Pharmacy (and phone)';
  String get pharmacyType => _isEs ? 'Tipo de farmacia' : 'Pharmacy type';
  String get localPharmacy => _isEs ? 'Farmacia local' : 'Local pharmacy';
  String get mailOrder => _isEs ? 'Pedido por correo' : 'Mail order';
  String get save => _isEs ? 'Guardar' : 'Save';
  String get saveOnce => _isEs ? 'Guardar una vez' : 'Save Once';
  String get iTakeBoth => _isEs ? 'Tomo ambos' : 'I Take Both';
  String get iTakeAll => _isEs ? 'Tomo todos' : 'I Take All';
  String get cancelScan => _isEs ? 'Cancelar escaneo' : 'Cancel Scan';
  String get useSelected => _isEs ? 'Usar seleccionados' : 'Use Selected';
  String get strength => _isEs ? 'Concentración' : 'Strength';
  String get strengthNotShown =>
      _isEs ? 'Concentración no indicada' : 'Strength not shown';
  String get directionsFrequency =>
      _isEs ? 'Indicaciones / frecuencia' : 'Directions / Frequency';
  String get saveSelected => _isEs ? 'Guardar seleccionados' : 'Save Selected';
  String get enterManually => _isEs ? 'Ingresar manualmente' : 'Enter Manually';
  String get scanLabelOrList => _isEs
      ? 'Escanear una etiqueta o lista de medicamentos'
      : 'Scan a Label or Medication List';
  String get canYouReadEveryItem =>
      _isEs ? '¿Puede leer cada artículo?' : 'Can you read every item?';
  String get scanLabelInstructions => _isEs
      ? 'Fotografíe una etiqueta de receta o de suplemento, o la lista completa de medicamentos del paquete de pastillas. Mantenga todo visible y legible.'
      : 'Photograph a prescription or supplement label, or the full pill-pack medication list. Keep everything visible and readable.';
  String get addAnotherPage =>
      _isEs ? 'Agregar otra página' : 'Add Another Page';
  String get logInAgainBeforeScanning => _isEs
      ? 'Inicie sesión de nuevo antes de escanear.'
      : 'Please log in again before scanning.';
  String get listTooLong => _isEs ? 'Lista demasiado larga' : 'List Too Long';
  String get couldNotReadLabel =>
      _isEs ? 'No se pudo leer la etiqueta' : 'Could Not Read Label';
  String get listTooLongBody => _isEs
      ? 'Esta lista de medicamentos tiene demasiadas filas para leerla en una sola foto. Fotografíe la mitad superior y la mitad inferior en escaneos separados.'
      : 'This medication list has too many rows to read in one photo. Please photograph the top half and bottom half as separate scans.';
  String get couldNotReadLabelBody => _isEs
      ? 'VitaLink no pudo leer esta etiqueta. Intente de nuevo con más luz, mantenga el teléfono firme o ingrese el medicamento manualmente.'
      : 'VitaLink could not read this medication label. Please try again with brighter lighting, hold the phone steady, or enter the medication manually.';
  String get noMedicationFound => _isEs
      ? 'No se encontró ningún medicamento o suplemento'
      : 'No Medication or Supplement Found';
  String get noMedicationFoundBody => _isEs
      ? 'El escaneo terminó, pero no se encontró el nombre de ningún medicamento o suplemento. Vuelva a tomar la foto con la etiqueta plana, cerca y bien iluminada, o ingréselo manualmente.'
      : 'The scan completed, but no medication or supplement name was found. Retake the photo with the label flat, close, and well-lit, or enter it manually.';
  String get youAlreadyHave => _isEs ? 'Ya tiene:' : 'You already have:';
  String get theLabelSays => _isEs ? 'La etiqueta dice:' : 'The label says:';
  String get whatWouldYouLikeToDo =>
      _isEs ? '¿Qué desea hacer?' : 'What would you like to do?';
  String get keepBoth => _isEs ? 'Conservar ambos' : 'Keep Both';
  String get removeMedication =>
      _isEs ? '¿Eliminar medicamento?' : 'Remove medication?';
  String get remove => _isEs ? 'Eliminar' : 'Remove';
  String get noMedicationsYet => _isEs
      ? 'Aún no hay medicamentos. Toque + para agregar.'
      : 'No medications yet. Tap + to add.';
  String get prescriptionsSection =>
      _isEs ? 'Medicamentos con receta' : 'Prescriptions';
  String get supplementsOtcSection =>
      _isEs ? 'Suplementos y de venta libre' : 'Supplements & OTC';
  String get readingMedicationInfo => _isEs
      ? 'Leyendo la información de sus medicamentos...'
      : 'Reading your medication information...';
  String get savingCheckingMedication => _isEs
      ? 'Guardando y verificando su medicamento...'
      : 'Saving and checking your medication...';
  String get noMedicationsAvailable =>
      _isEs ? 'No hay medicamentos disponibles.' : 'No medications available.';
  String get unnamedMedication =>
      _isEs ? 'Medicamento sin nombre' : 'Unnamed Medication';
  String isMailOrderPharmacy(String name) => _isEs
      ? '¿$name es una farmacia de pedidos por correo?'
      : 'Is $name a mail-order pharmacy?';
  String whichPharmacyIs(String name) =>
      _isEs ? '¿Cuál farmacia es $name?' : 'Which pharmacy is $name?';
  String whichProviderIs(String name) =>
      _isEs ? '¿Cuál proveedor es $name?' : 'Which provider is $name?';
  String appearsMoreThanOnce(String name) =>
      _isEs ? '$name aparece más de una vez' : '$name appears more than once';
  String listShowsTimes(String name, String dose, int times) => _isEs
      ? 'La lista muestra $name $dose $times veces. ¿Toma cada entrada de la lista o VitaLink debe guardar este medicamento una sola vez?'
      : 'The list shows $name $dose $times times. Do you take every listed entry, or should VitaLink save this medication once?';
  String selectEveryStrength() => _isEs
      ? 'Seleccione cada concentración que toma actualmente. Elija ambas si las dos dosis son parte de su horario de medicamentos.'
      : 'Select every strength you currently take. Choose both if both doses are part of your medication schedule.';
  String quantityValue(String quantity) =>
      _isEs ? 'Cantidad $quantity' : 'Quantity $quantity';
  String rowStrength(int row, String strength) =>
      _isEs ? 'Fila $row: $strength' : 'Row $row: $strength';
  String reviewMedicationsTitle(int count) =>
      _isEs ? 'Revisar $count medicamentos' : 'Review $count Medications';
  String confirmEveryMedication() => _isEs
      ? 'Compare cada medicamento con la lista impresa. VitaLink no adivinará las indicaciones que falten.'
      : 'Confirm every medication against the printed list. VitaLink will not guess missing directions.';
  String medicationNumber(int number) =>
      _isEs ? 'Medicamento $number' : 'Medication $number';
  String medicationListSaved(int added, int updated) => _isEs
      ? 'Lista de medicamentos guardada: $added agregados, $updated actualizados.'
      : 'Medication list saved: $added added, $updated updated.';
  String medicationsFor(String name) =>
      _isEs ? 'Medicamentos – $name' : 'Medications – $name';

  // Doctors, appointments, NPI lookup, camera
  String get addDoctor => _isEs ? 'Agregar médico' : 'Add Doctor';
  String get editDoctor => _isEs ? 'Editar médico' : 'Edit Doctor';
  String get specialty => _isEs ? 'Especialidad' : 'Specialty';
  String get clinic => _isEs ? 'Clínica' : 'Clinic';
  String get primaryCareProvider =>
      _isEs ? 'Proveedor de atención primaria' : 'Primary care provider';
  String get npiNeedsReviewSave => _isEs
      ? 'El NPI necesita revisión. Guarde para revisar las coincidencias.'
      : 'NPI needs review. Save to review matches.';
  String get npiNotVerifiedSave => _isEs
      ? 'NPI no verificado. Guarde para volver a buscar.'
      : 'NPI not verified. Save to retry lookup.';
  String get registryRecord => _isEs ? 'Registro oficial' : 'Registry record';
  String get savingCheckingDoctor => _isEs
      ? 'Guardando y verificando su médico...'
      : 'Saving and checking your doctor...';
  String get couldNotCheckDoctorBody => _isEs
      ? 'No pudimos verificar a este médico en este momento. Su información se guardó, así que puede intentarlo de nuevo.'
      : 'We could not check this doctor right now. Your information was saved, so you can try again.';
  String get couldNotCheckDoctor =>
      _isEs ? 'No se pudo verificar al médico' : 'Could not check doctor';
  String get doctorNotVerified =>
      _isEs ? 'Médico no verificado' : 'Doctor not verified';
  String get sessionNotVerifiedRetryDoctor => _isEs
      ? 'VitaLink no pudo verificar su sesión. Inicie sesión de nuevo y vuelva a intentar con este médico.'
      : 'VitaLink could not verify your signed-in session. Please sign in again, then retry this doctor.';
  String get removeDoctor => _isEs ? '¿Eliminar médico?' : 'Remove doctor?';
  String get noDoctorsAdded =>
      _isEs ? 'No se han agregado médicos.' : 'No doctors added.';
  String get vaProvider => _isEs ? 'Proveedor de VA' : 'VA Provider';
  String get noDoctorsAvailable =>
      _isEs ? 'No hay médicos disponibles.' : 'No doctors available.';
  String get unnamedDoctor => _isEs ? 'Médico sin nombre' : 'Unnamed Doctor';
  String get createdFromVitaLink =>
      _isEs ? 'Creado desde VitaLink.' : 'Created from VitaLink.';
  String get addAppointmentToCalendarShare => _isEs
      ? 'Agregue esta cita de VitaLink a su calendario.'
      : 'Add this VitaLink appointment to your calendar.';
  String get addToPhoneCalendar =>
      _isEs ? '¿Agregar al calendario del teléfono?' : 'Add to phone calendar?';
  String get addToCalendar =>
      _isEs ? 'Agregar al calendario' : 'Add to Calendar';
  String get addAppointment => _isEs ? 'Agregar cita' : 'Add Appointment';
  String get editAppointment => _isEs ? 'Editar cita' : 'Edit Appointment';
  String get doctor => _isEs ? 'Médico' : 'Doctor';
  String get addNewDoctor => _isEs ? 'Agregar nuevo médico' : 'Add New Doctor';
  String get doctorName => _isEs ? 'Nombre del médico' : 'Doctor Name';
  String get dateTime => _isEs ? 'Fecha / hora' : 'Date / Time';
  String get notes => _isEs ? 'Notas' : 'Notes';
  String get doctorNameRequired =>
      _isEs ? 'El nombre del médico es obligatorio' : 'Doctor name is required';
  String get removeAppointment =>
      _isEs ? '¿Eliminar cita?' : 'Remove appointment?';
  String get noAppointmentsAdded =>
      _isEs ? 'No se han agregado citas.' : 'No appointments added.';
  String get whereIsThisDoctor =>
      _isEs ? '¿Dónde está este médico?' : 'Where is this doctor?';
  String get doctorZipCode =>
      _isEs ? 'Código postal del médico' : 'Doctor ZIP code';
  String get enterFiveDigitZip => _isEs
      ? 'Ingrese un código postal de 5 dígitos'
      : 'Enter a 5-digit ZIP code';
  String get leaveUnresolved =>
      _isEs ? 'Dejar sin resolver' : 'Leave unresolved';
  String get searchZip => _isEs ? 'Buscar código postal' : 'Search ZIP';
  String get pharmacyZipCode =>
      _isEs ? 'Código postal de la farmacia' : 'Pharmacy ZIP code';
  String get enterFiveDigitZipSentence => _isEs
      ? 'Ingrese un código postal de cinco dígitos.'
      : 'Enter a five-digit ZIP code.';
  String get search => _isEs ? 'Buscar' : 'Search';
  String get whatTypeOfDoctor =>
      _isEs ? '¿Qué tipo de médico es?' : 'What type of doctor is this?';
  String get narrowNpiMatches => _isEs
      ? 'Esto puede reducir las coincidencias del NPI antes de que elija un proveedor.'
      : 'This can narrow the NPI matches before you choose a provider.';
  String get doctorType => _isEs ? 'Tipo de médico' : 'Doctor type';
  String get doctorTypeOptional =>
      _isEs ? 'Tipo de médico (opcional)' : 'Doctor type (optional)';
  String get narrowMatches =>
      _isEs ? 'Reducir coincidencias' : 'Narrow matches';
  String get vaProviderVerified =>
      _isEs ? 'Proveedor de VA verificado' : 'VA provider verified';
  String get npiVerified => _isEs ? 'NPI verificado' : 'NPI verified';
  String get npiMatchNeedsReview => _isEs
      ? 'La coincidencia del NPI necesita revisión'
      : 'NPI match needs review';
  String get npiNotVerified => _isEs ? 'NPI no verificado' : 'NPI not verified';
  String get primaryCare => _isEs ? 'Atención primaria' : 'Primary Care';
  String get noMatchingRecordsTryPharmacyZip => _isEs
      ? 'No hay registros que coincidan aquí. Pruebe con el código postal de la farmacia o déjelo sin resolver.'
      : 'No matching records here. Try the pharmacy ZIP, or leave it unresolved.';
  String get noMatchingRecords => _isEs
      ? 'No se encontraron registros que coincidan. Déjelo sin resolver si ninguno coincide.'
      : 'No matching records found. Leave it unresolved if none match.';
  String get chooseMatchingRecord => _isEs
      ? 'Elija el registro que coincida o déjelo sin resolver.'
      : 'Choose the matching record, or leave it unresolved.';
  String get provider => _isEs ? 'Proveedor' : 'Provider';
  String get previouslyConfirmed =>
      _isEs ? 'Confirmado anteriormente' : 'Previously confirmed';
  String get inYourZipCode =>
      _isEs ? 'En su código postal' : 'In your ZIP code';
  String get searchAnotherZip =>
      _isEs ? 'Buscar otro código postal' : 'Search another ZIP';
  String get addAnotherSide => _isEs ? 'Agregar otro lado' : 'Add Another Side';
  String get noCameraFound => _isEs
      ? 'No se encontró ninguna cámara en este dispositivo.'
      : 'No camera was found on this device.';
  String get cameraCouldNotOpen => _isEs
      ? 'No se pudo abrir la cámara. Revise el permiso de la cámara.'
      : 'Camera could not be opened. Please check camera permission.';
  String get retakeIfBlurry => _isEs
      ? 'Si la imagen está borrosa, oscura o cortada, vuelva a tomarla.'
      : 'If the image is blurry, dark, or cut off, retake it.';
  String get usePhoto => _isEs ? 'Usar foto' : 'Use Photo';
  String get retake => _isEs ? 'Volver a tomar' : 'Retake';
  String get takingPhoto => _isEs ? 'Tomando foto...' : 'Taking Photo...';
  String get takePhoto => _isEs ? 'Tomar foto' : 'Take Photo';
  String get done => _isEs ? 'Listo' : 'Done';
  String get scanInsuranceCard =>
      _isEs ? 'Escanear tarjeta de seguro' : 'Scan Insurance Card';
  String get preparingScanner =>
      _isEs ? 'Preparando el escáner...' : 'Preparing scanner...';
  String npiVerifiedValue(String npi) =>
      _isEs ? 'NPI verificado: $npi' : 'NPI verified: $npi';
  String vaProviderVerifiedAt(String facility) => _isEs
      ? 'Proveedor de VA verificado: $facility'
      : 'VA provider verified: $facility';
  String couldNotFindDoctorNearZip(String name) => _isEs
      ? 'No pudimos encontrar a $name a menos de 15 millas de ese código postal. Revise el nombre y el código postal e intente de nuevo.'
      : 'We could not find $name within 15 miles of that ZIP code. Check the name and ZIP, then try again.';
  String vaProviderAt(String facility) =>
      _isEs ? 'Proveedor de VA - $facility' : 'VA Provider - $facility';
  String doctorsFor(String name) =>
      _isEs ? 'Médicos – $name' : 'Doctors – $name';
  String appointmentWith(String name) =>
      _isEs ? 'Cita con $name' : 'Appointment with $name';
  String specialtyValue(String specialty) =>
      _isEs ? 'Especialidad: $specialty' : 'Specialty: $specialty';
  String enterZipToNarrow(String name) => _isEs
      ? 'Ingrese un código postal específico para reducir los resultados de $name.'
      : 'Enter a specific ZIP code to narrow the results for $name.';
  String enterZipFor(String name) => _isEs
      ? 'Ingrese el código postal de $name.'
      : 'Enter the ZIP code for $name.';
  String couldNotFindInRegisteredZip(String name, String zip) => _isEs
      ? 'No pudimos encontrar a $name en su código postal registrado ($zip). Ingrese el código postal donde se encuentra el médico.'
      : 'We couldn\'t find $name in your registered ZIP ($zip). Enter the ZIP code where the doctor is located.';
  String aboutMilesAway(String miles) =>
      _isEs ? 'A unas $miles millas' : 'About $miles miles away';
  String photoFailed(Object error) =>
      _isEs ? 'No se pudo tomar la foto: $error' : 'Photo failed: $error';
  String photosAdded(int count) =>
      _isEs ? '$count foto(s) agregada(s)' : '$count photo(s) added';
  String scanFailed(Object error) =>
      _isEs ? 'Falló el escaneo: $error' : 'Scan failed: $error';

  // Insurance policies, cards, declaration pages
  String get addInsurancePolicy =>
      _isEs ? 'Agregar póliza de seguro' : 'Add Insurance Policy';
  String get editInsurancePolicy =>
      _isEs ? 'Editar póliza de seguro' : 'Edit Insurance Policy';
  String get carrier => _isEs ? 'Aseguradora' : 'Carrier';
  String get policyNumber => _isEs ? 'Póliza n.º' : 'Policy #';
  String get memberId => _isEs ? 'ID de miembro' : 'Member ID';
  String get policyType => _isEs ? 'Tipo de póliza' : 'Policy Type';
  String get removeInsurancePolicy =>
      _isEs ? '¿Eliminar póliza de seguro?' : 'Remove insurance policy?';
  String get noProfileFound =>
      _isEs ? 'No se encontró ningún perfil' : 'No profile found';
  String get noInsurancePoliciesYet => _isEs
      ? 'Aún no hay pólizas de seguro. Toque + para agregar.'
      : 'No insurance policies yet. Tap + to add.';
  String get unnamedPolicy => _isEs ? 'Póliza sin nombre' : 'Unnamed Policy';
  String get processingInsurance =>
      _isEs ? 'Procesando el seguro...' : 'Processing insurance...';
  String get scanInsurancePolicy =>
      _isEs ? 'Escanear póliza de seguro' : 'Scan Insurance Policy';
  String get canYouReadPolicyPage => _isEs
      ? '¿Puede leer la página de la póliza?'
      : 'Can you read the policy page?';
  String get fillScreenWithPolicyPage => _isEs
      ? 'Mantenga el teléfono firme y llene la pantalla con la página de la póliza.'
      : 'Hold the phone steady and fill the screen with the policy page.';
  String get duplicateDetected =>
      _isEs ? 'Duplicado detectado' : 'Duplicate Detected';
  String get addNew => _isEs ? 'Agregar nuevo' : 'Add New';
  String get updateExisting =>
      _isEs ? 'Actualizar existente' : 'Update Existing';
  String get removePolicy => _isEs ? '¿Eliminar póliza?' : 'Remove policy?';
  String get mergedIntoExistingPolicy => _isEs
      ? 'Combinada con la póliza existente'
      : 'Merged into existing policy';
  String get createdNewPolicy =>
      _isEs ? 'Póliza nueva creada' : 'Created new policy';
  String get policyUpdated => _isEs ? 'Póliza actualizada' : 'Policy updated';
  String get newInsurancePolicy =>
      _isEs ? 'Nueva póliza de seguro' : 'New Insurance Policy';
  String get groupNumber => _isEs ? 'Grupo n.º' : 'Group #';
  String get insuredName => _isEs ? 'Nombre del asegurado' : 'Insured Name';
  String get beneficiary => _isEs ? 'Beneficiario' : 'Beneficiary';
  String get cardLinkedToPolicy =>
      _isEs ? 'Tarjeta vinculada a la póliza' : 'Card linked to policy';
  String get deletePolicyQuestion =>
      _isEs ? '¿Eliminar póliza?' : 'Delete Policy?';
  String get deletePolicyBody => _isEs
      ? 'Esto eliminará esta póliza de forma permanente.'
      : 'This will permanently remove this policy.';
  String get delete => _isEs ? 'Eliminar' : 'Delete';
  String get policyDeleted => _isEs ? 'Póliza eliminada' : 'Policy deleted';
  String get declarationPageAdded =>
      _isEs ? 'Página de declaración agregada' : 'Declaration page added';
  String get declarationPageCaptured =>
      _isEs ? 'Página de declaración capturada' : 'Declaration page captured';
  String get insurancePolicy => _isEs ? 'Póliza de seguro' : 'Insurance Policy';
  String get insured => _isEs ? 'Asegurado' : 'Insured';
  String get benefits => _isEs ? 'Beneficios' : 'Benefits';
  String get noBenefitsExtracted =>
      _isEs ? 'No se extrajeron beneficios.' : 'No benefits extracted.';
  String get viewCards => _isEs ? 'Ver tarjetas' : 'View Cards';
  String get declarationPages =>
      _isEs ? 'Páginas de declaración' : 'Declaration Pages';
  String get upload => _isEs ? 'Subir' : 'Upload';
  String get camera => _isEs ? 'Cámara' : 'Camera';
  String get noDeclarationPagesUploaded => _isEs
      ? 'No se han subido páginas de declaración.'
      : 'No declaration pages uploaded.';
  String get unableToLoadCards =>
      _isEs ? 'No se pudieron cargar las tarjetas' : 'Unable to load cards';
  String get noCardsForPolicy =>
      _isEs ? 'No hay tarjetas para esta póliza' : 'No cards for this policy';
  String get copays => _isEs ? 'Copagos' : 'Co-pays';
  String get noImageAvailable =>
      _isEs ? 'No hay imagen disponible' : 'No image available';
  String get cardViewer => _isEs ? 'Visor de tarjeta' : 'Card Viewer';
  String get cameraPermissionNotGranted => _isEs
      ? 'No se otorgó el permiso de la cámara'
      : 'Camera permission not granted';
  String get scanBackOfCard =>
      _isEs ? '¿Escanear el reverso de la tarjeta?' : 'Scan Back of Card?';
  String get scanBack => _isEs ? 'Escanear reverso' : 'Scan Back';
  String get cardSavedFrontBack => _isEs
      ? 'Tarjeta guardada (frente y reverso)'
      : 'Card saved (front + back)';
  String get cardDeleted => _isEs ? 'Tarjeta eliminada' : 'Card deleted';
  String get unableToLoadInsuranceCards => _isEs
      ? 'No se pudieron cargar las tarjetas de seguro.'
      : 'Unable to load insurance cards.';
  String get noInsuranceCardsFound => _isEs
      ? 'No se encontraron tarjetas de seguro'
      : 'No insurance cards found';
  String get insuranceCard => _isEs ? 'Tarjeta de seguro' : 'Insurance Card';
  String get insuranceCardLower =>
      _isEs ? 'Tarjeta de seguro' : 'Insurance card';
  String get unableToLoadCopays => _isEs
      ? 'No se pudieron cargar los copagos de esta tarjeta.'
      : 'Unable to load co-pays for this card.';
  String get copaysNotFound =>
      _isEs ? 'No se encontraron copagos' : 'Co-pays Not Found';
  String get medicareCopays =>
      _isEs ? 'Copagos de Medicare' : 'Medicare Co-pays';
  String get medicarePlan => _isEs ? 'Plan de Medicare' : 'Medicare Plan';
  String get moopInNetwork =>
      _isEs ? 'MOOP dentro de la red' : 'MOOP In-Network';
  String get moopCombined => _isEs ? 'MOOP combinado' : 'MOOP Combined';
  String get cmsNoCopayRows => _isEs
      ? 'CMS encontró este plan, pero aún no se asignaron los copagos principales.'
      : 'CMS found this plan, but no key co-pay rows were mapped yet.';
  String get noCardImagesAvailable => _isEs
      ? 'No hay imágenes de la tarjeta disponibles'
      : 'No card images available';
  String get insuranceCardShareText => _isEs
      ? 'Adjunto mi tarjeta de seguro para sus registros.'
      : 'Please find my insurance card attached for your records.';
  String get copaysUnavailable =>
      _isEs ? 'Copagos no disponibles' : 'Co-pays unavailable';
  String get addBackOfCard =>
      _isEs ? 'Agregar reverso de la tarjeta' : 'Add Back of Card';
  String get replaceBackOfCard =>
      _isEs ? 'Reemplazar reverso de la tarjeta' : 'Replace Back of Card';
  String get shareThisCard =>
      _isEs ? 'Compartir esta tarjeta' : 'Share This Card';
  String get fileNotFound =>
      _isEs ? 'No se encontró el archivo' : 'File not found';
  String get newPolicy => _isEs ? 'Nueva póliza' : 'New Policy';
  String get editPolicy => _isEs ? 'Editar póliza' : 'Edit Policy';
  String get company => _isEs ? 'Compañía' : 'Company';
  String get plan => _isEs ? 'Plan' : 'Plan';
  String get member => _isEs ? 'Miembro' : 'Member';
  String policyAlreadyExists(String carrier, String policy) => _isEs
      ? 'La póliza \'$carrier – $policy\' ya existe.'
      : 'Policy \'$carrier – $policy\' already exists.';
  String policyScanFailed(Object error) => _isEs
      ? 'Falló el escaneo de la póliza: $error'
      : 'Policy scan failed: $error';
  String policyNumberValue(String value) =>
      _isEs ? 'Póliza n.º: $value' : 'Policy #: $value';
  String pageValue(String page) => _isEs ? 'Página: $page' : 'Page: $page';
  String cardNumber(int number) => _isEs ? 'Tarjeta $number' : 'Card $number';
  String scanBackPrompt(int count) => _isEs
      ? 'Tiene $count imagen(es).\n\nDé vuelta la tarjeta y escanee el reverso.'
      : 'You have $count image(s).\n\nFlip the card and scan the back.';
  String scannerError(Object error) =>
      _isEs ? 'Error del escáner: $error' : 'Scanner error: $error';
  String insuranceCardSubject(String carrier) =>
      _isEs ? 'Tarjeta de seguro – $carrier' : 'Insurance Card – $carrier';
  String declarationPageTitle(String suffix) =>
      _isEs ? 'Página de declaración$suffix' : 'Declaration Page$suffix';

  // Profiles, household and profile sharing
  String get removeVeteranStatus =>
      _isEs ? '¿Quitar el estado de veterano?' : 'Remove Veteran status?';
  String get removeVeteranStatusBody => _isEs
      ? 'Esto también quitará de este perfil la selección de atención médica de VA y el aviso de emergencia de VA.'
      : 'This will also remove the VA health care selection and VA emergency notice from this profile.';
  String get keepVeteranStatus =>
      _isEs ? 'Conservar el estado de veterano' : 'Keep Veteran Status';
  String get editProfile => _isEs ? 'Editar perfil' : 'Edit Profile';
  String get fullNameFirstLast => _isEs
      ? 'Nombre completo (nombre y apellido)'
      : 'Full Name (First & Last)';
  String get firstAndLastName =>
      _isEs ? 'Nombre y apellido' : 'First and Last Name';
  String get requiredForEmergencyId => _isEs
      ? 'Necesario para la identificación en una emergencia'
      : 'Required for emergency identification';
  String get enterFirstLastName =>
      _isEs ? 'Ingrese nombre y apellido' : 'Enter first & last name';
  String get dobMmDdYyyy =>
      _isEs ? 'Fecha de nacimiento (MM/DD/AAAA)' : 'Date of Birth (MM/DD/YYYY)';
  String get emergencyContactLabel =>
      _isEs ? 'Contacto de emergencia' : 'Emergency Contact';
  String get enterFullName =>
      _isEs ? 'Ingrese el nombre completo' : 'Enter full name';
  String get emergencyPhone =>
      _isEs ? 'Teléfono de emergencia' : 'Emergency Phone';
  String get enterValidPhone =>
      _isEs ? 'Ingrese un teléfono válido' : 'Enter valid phone';
  String get removeEmergencyContact =>
      _isEs ? 'Quitar contacto de emergencia' : 'Remove emergency contact';
  String get addAnotherEmergencyContact => _isEs
      ? 'Agregar otro contacto de emergencia'
      : 'Add Another Emergency Contact';
  String get veteran => _isEs ? 'Veterano' : 'Veteran';
  String get useVaHealthCare =>
      _isEs ? '¿Usa la atención médica de VA?' : 'Do you use VA health care?';
  String get sessionErrorLogInAgain => _isEs
      ? 'Error de sesión. Inicie sesión de nuevo.'
      : 'Session error. Please log in again.';
  String get failedToUpdateProfile => _isEs
      ? 'No se pudo actualizar el perfil ❌'
      : 'Failed to update profile ❌';
  String get profileUpdatedCheck =>
      _isEs ? 'Perfil actualizado ✅' : 'Profile updated ✅';
  String get userProfile => _isEs ? 'Perfil de usuario' : 'User Profile';
  String get dateHint => _isEs ? 'mm/dd/aaaa' : 'mm/dd/yyyy';
  String get areYouVeteran =>
      _isEs ? '¿Es usted veterano?' : 'Are you a Veteran?';
  String get saveChanges => _isEs ? 'Guardar cambios' : 'Save Changes';
  String get profileUpdated => _isEs ? 'Perfil actualizado' : 'Profile updated';
  String get updateError => _isEs ? 'Error al actualizar' : 'Update error';
  String get agencyName => _isEs ? 'Nombre de la agencia' : 'Agency Name';
  String get agencyAddress =>
      _isEs ? 'Dirección de la agencia' : 'Agency Address';
  String get npnNotEditable =>
      _isEs ? 'NPN (no editable)' : 'NPN (not editable)';
  String get newPasswordOptional =>
      _isEs ? 'Nueva contraseña (opcional)' : 'New Password (optional)';
  String get newHouseholdProfile =>
      _isEs ? 'Nuevo perfil familiar' : 'New Household Profile';
  String get nameIsRequired =>
      _isEs ? 'El nombre es obligatorio' : 'Name is required';
  String get bloodTypeOptional =>
      _isEs ? 'Tipo de sangre (opcional)' : 'Blood Type (optional)';
  String get medicalConditions =>
      _isEs ? 'Afecciones médicas' : 'Medical Conditions';
  String get saveHouseholdProfile =>
      _isEs ? 'Guardar perfil familiar' : 'Save Household Profile';
  String get deleteProfile => _isEs ? 'Eliminar perfil' : 'Delete Profile';
  String get addProfileFromInvite =>
      _isEs ? 'Agregar perfil desde una invitación' : 'Add Profile from Invite';
  String get useProfileShareCode => _isEs
      ? 'Use un código para compartir perfil de un familiar o cuidador.'
      : 'Use a profile share code from a family member or caregiver.';
  String get unnamedProfile => _isEs ? 'Perfil sin nombre' : 'Unnamed Profile';
  String get sharingEndedCopy => _isEs
      ? 'Se dejó de compartir. Puede conservar esta copia desactivada o eliminarla.'
      : 'Sharing ended. You can keep this disabled copy or delete it.';
  String get currentlyActive =>
      _isEs ? 'Activo actualmente' : 'Currently Active';
  String get cannotDeleteActiveProfile => _isEs
      ? 'No se puede eliminar el perfil activo'
      : 'Cannot delete the active profile';
  String get removeHouseholdProfile =>
      _isEs ? 'Eliminar perfil familiar' : 'Remove Household Profile';
  String get profileManager =>
      _isEs ? 'Administrador de perfiles' : 'Profile Manager';
  String get activeProfileCaps => _isEs ? 'PERFIL ACTIVO' : 'ACTIVE PROFILE';
  String get householdMemberCaps =>
      _isEs ? 'MIEMBRO DE LA FAMILIA' : 'HOUSEHOLD MEMBER';
  String get switchToThisProfile =>
      _isEs ? 'Cambiar a este perfil' : 'Switch to this profile';
  String get chooseOneSectionToShare => _isEs
      ? 'Elija al menos una sección para compartir.'
      : 'Choose at least one section to share.';
  String get enterEmailAndPhoneForShare => _isEs
      ? 'Ingrese el correo electrónico y el número de teléfono para compartir.'
      : 'Enter both email and phone number for this share.';
  String get logInAgainBeforeSharing => _isEs
      ? 'Inicie sesión de nuevo antes de compartir un perfil.'
      : 'Please log in again before sharing a profile.';
  String get unableToFinishShareCode => _isEs
      ? 'No se pudo terminar de crear este código para compartir.'
      : 'Unable to finish creating this share code.';
  String get shareCodeCreated => _isEs
      ? 'Código para compartir creado. Entrégueselo al cuidador en persona dentro de 6 horas.'
      : 'Share code created. Give it to the caregiver in person within 6 hours.';
  String get unableToCreateShareLink => _isEs
      ? 'No se pudo crear el enlace para compartir.'
      : 'Unable to create share link.';
  String get enterShareCodeFirst => _isEs
      ? 'Primero ingrese el código para compartir.'
      : 'Enter the share code first.';
  String get logInAgainBeforeAccepting => _isEs
      ? 'Inicie sesión de nuevo antes de aceptar un perfil compartido.'
      : 'Please log in again before accepting a profile share.';
  String get profileShareAccepted => _isEs
      ? 'Perfil compartido aceptado. Las actualizaciones aparecerán en Actualizaciones de perfil.'
      : 'Profile share accepted. Updates will appear in Profile Updates.';
  String get unableToAcceptShareCode => _isEs
      ? 'No se pudo aceptar el código para compartir.'
      : 'Unable to accept share code.';
  String get revokeAccessQuestion =>
      _isEs ? '¿Revocar el acceso?' : 'Revoke Access?';
  String get stopSharingUpdates =>
      _isEs ? 'Dejar de compartir actualizaciones' : 'Stop Sharing Updates';
  String get logInAgainBeforeChangingSharing => _isEs
      ? 'Inicie sesión de nuevo antes de cambiar cómo comparte el perfil.'
      : 'Please log in again before changing profile sharing.';
  String get profileAccessRevoked =>
      _isEs ? 'Acceso al perfil revocado.' : 'Profile access revoked.';
  String get unableToRevokeAccess => _isEs
      ? 'No se pudo revocar el acceso al perfil.'
      : 'Unable to revoke profile access.';
  String get shareHasNoInviteCode => _isEs
      ? 'Este perfil compartido no tiene código de invitación.'
      : 'This share does not have an invite code.';
  String get shareCodeCopied => _isEs
      ? 'Código copiado. Entrégueselo al cuidador en persona.'
      : 'Share code copied. Give it to the caregiver in person.';
  String get shareMustBeAccepted => _isEs
      ? 'El perfil compartido debe aceptarse antes de poder enviar actualizaciones.'
      : 'A shared profile must be accepted before updates can be sent.';
  String get currentProfileUpdateSent => _isEs
      ? 'Se envió la actualización actual del perfil.'
      : 'Current profile update sent.';
  String get noRecipientsReady => _isEs
      ? 'No hay destinatarios conectados listos para esta actualización.'
      : 'No connected recipients are ready for this update.';
  String get profileSent => _isEs ? 'Perfil enviado' : 'Profile Sent';
  String get profileUpdateSentToConnected => _isEs
      ? 'La actualización actual del perfil se envió a los perfiles conectados.'
      : 'The current profile update was sent to connected profiles.';
  String get connectedProfiles =>
      _isEs ? 'Perfiles conectados' : 'Connected profiles';
  String get shareProfileExplainer => _isEs
      ? 'Comparta las actualizaciones seleccionadas del perfil con un familiar o cuidador. Las actualizaciones son temporales, están cifradas y se eliminan después de que los dispositivos conectados las aplican.'
      : 'Share selected profile updates with a family member or caregiver. Updates are temporary, encrypted, and removed after connected devices apply them.';
  String get shareThisProfile =>
      _isEs ? 'Compartir este perfil' : 'Share this profile';
  String get familyMemberEmail =>
      _isEs ? 'Correo electrónico del familiar' : 'Family member email';
  String get familyMemberPhone =>
      _isEs ? 'Teléfono del familiar' : 'Family member phone';
  String get emergencyProfile =>
      _isEs ? 'Perfil de emergencia' : 'Emergency profile';
  String get insuranceCardsLower =>
      _isEs ? 'Tarjetas de seguro' : 'Insurance cards';
  String get insurancePoliciesLower =>
      _isEs ? 'Pólizas de seguro' : 'Insurance policies';
  String get createShareCode =>
      _isEs ? 'Crear código para compartir' : 'Create Share Code';
  String get sendCurrentProfileUpdate => _isEs
      ? 'Enviar la actualización actual del perfil'
      : 'Send Current Profile Update';
  String get whoHasAccess => _isEs ? 'Quién tiene acceso' : 'Who has access';
  String get noActiveProfileShares => _isEs
      ? 'Aún no hay perfiles compartidos activos.'
      : 'No active profile shares yet.';
  String get acceptSharedProfile =>
      _isEs ? 'Aceptar un perfil compartido' : 'Accept a shared profile';
  String get shareCodeLower => _isEs ? 'Código para compartir' : 'Share code';
  String get acceptShareCode =>
      _isEs ? 'Aceptar código para compartir' : 'Accept Share Code';
  String get shareCodeTitle => _isEs ? 'Código para compartir' : 'Share Code';
  String get expiresSixHours => _isEs
      ? 'Vence 6 horas después de crearse'
      : 'Expires 6 hours after it was created';
  String get copyShareCode =>
      _isEs ? 'Copiar código para compartir' : 'Copy Share Code';
  String get revokeAccess => _isEs ? 'Revocar acceso' : 'Revoke Access';
  String get sharedProfileLower =>
      _isEs ? 'Perfil compartido' : 'Shared profile';
  String get enterInviteCodeFirst => _isEs
      ? 'Primero ingrese el código de invitación del perfil.'
      : 'Enter the profile invite code first.';
  String get logInBeforeAcceptingInvite => _isEs
      ? 'Inicie sesión antes de aceptar una invitación de perfil.'
      : 'Please log in before accepting a profile invite.';
  String get unableToAcceptInvite => _isEs
      ? 'No se pudo aceptar esta invitación de perfil.'
      : 'Unable to accept this profile invite.';
  String get inviteCouldNotComplete => _isEs
      ? 'No se pudo completar esta invitación de perfil.'
      : 'This profile invite could not be completed.';
  String get profileInviteAccepted => _isEs
      ? 'Invitación aceptada. El perfil compartido aparecerá cuando quien lo comparte envíe la actualización actual del perfil.'
      : 'Profile invite accepted. The shared profile will appear when the sender sends the current profile update.';
  String get sharedProfileAdded =>
      _isEs ? 'Perfil compartido agregado.' : 'Shared profile added.';
  String get profileAdded => _isEs ? 'Perfil agregado' : 'Profile Added';
  String get sharedProfileAddedSwitch => _isEs
      ? 'Se agregó el perfil compartido. Ahora puede cambiar a él.'
      : 'The shared profile has been added. You can switch to it now.';
  String get profileInvite => _isEs ? 'Invitación de perfil' : 'Profile Invite';
  String get enterInviteCodeExplainer => _isEs
      ? 'Ingrese el código de invitación de un familiar o cuidador para agregar su perfil compartido de VitaLink.'
      : 'Enter the invite code from a family member or caregiver to add their shared VitaLink profile.';
  String get inviteCode => _isEs ? 'Código de invitación' : 'Invite Code';
  String get addingProfile =>
      _isEs ? 'Agregando perfil...' : 'Adding Profile...';
  String get addSharedProfile =>
      _isEs ? 'Agregar perfil compartido' : 'Add Shared Profile';
  String get logInAgainToCheckUpdates => _isEs
      ? 'Inicie sesión de nuevo para revisar las actualizaciones del perfil.'
      : 'Please log in again to check profile updates.';
  String get unableToLoadProfileUpdates => _isEs
      ? 'No se pudieron cargar las actualizaciones del perfil.'
      : 'Unable to load profile updates.';
  String get updateCouldNotApply => _isEs
      ? 'No se pudo aplicar esta actualización.'
      : 'This update could not be applied.';
  String get profileUpdateApplied =>
      _isEs ? 'Actualización del perfil aplicada.' : 'Profile update applied.';
  String get connectedProfileUpdates => _isEs
      ? 'Actualizaciones de perfiles conectados'
      : 'Connected profile updates';
  String get updatesTemporarilyStored => _isEs
      ? 'Las actualizaciones se guardan temporalmente, están cifradas y se eliminan después de que los dispositivos conectados las aplican.'
      : 'Updates are temporarily stored, encrypted, and removed after connected devices apply them.';
  String get noProfileUpdatesWaiting => _isEs
      ? 'No hay actualizaciones de perfil pendientes en este momento.'
      : 'No profile updates are waiting right now.';
  String get sharedProfileTitle =>
      _isEs ? 'Perfil compartido' : 'Shared Profile';
  String get applyUpdate => _isEs ? 'Aplicar actualización' : 'Apply Update';
  String emergencyContactTextIntro(String contact, String patient) => _isEs
      ? 'Hola $contact:\n\n$patient lo eligió como contacto de emergencia en VitaLink.\n\nVitaLink guarda información de salud importante que puede ayudar en una emergencia si alguien está inconsciente o no puede comunicarse.'
      : 'Hi $contact,\n\n$patient selected you as an emergency contact in VitaLink.\n\nVitaLink stores important health information that can help in an emergency if someone is unconscious or unable to communicate.';
  String emergencyContactTextAgent(
          String patient, String agentName, String agentPhone) =>
      _isEs
          ? '\n\nVitaLink se ofreció a través del agente de seguros de $patient:\n$agentName\n$agentPhone\nComuníquese con el agente si tiene preguntas o desea más información.'
          : '\n\nVitaLink was provided through $patient\'s insurance agent:\n$agentName\n$agentPhone\nContact the agent if you have questions or would like more information.';
  String emergencyContactTextMoreInfo() => _isEs
      ? 'Más información: https://myvitalink.app'
      : 'More information: https://myvitalink.app';
  String emergencyContactNumberTitle(int number) =>
      _isEs ? 'Contacto de emergencia $number' : 'Emergency Contact $number';
  String permanentlyRemoveProfile(String name) => _isEs
      ? '¿Eliminar permanentemente "$name" de los perfiles familiares?'
      : 'Permanently remove "$name" from household profiles?';
  String confirmRemoveHouseholdProfile(String name) => _isEs
      ? '¿Está seguro de que desea eliminar a $name? Esto no se puede deshacer.'
      : 'Are you sure you want to remove $name? This cannot be undone.';
  String emailValue(String email) =>
      _isEs ? 'Correo electrónico: $email' : 'Email: $email';
  String revokeAccessBody() => _isEs
      ? 'Este cuidador ya no recibirá información nueva ni actualizada de este perfil. La información compartida anteriormente puede quedar en su dispositivo y no se puede recuperar ni eliminar a distancia.'
      : 'This caregiver will no longer receive new or updated information for this profile. Information previously shared may remain on their device and cannot be recalled.';
  String codeValue(String code) => _isEs ? 'Código: $code' : 'Code: $code';

  // Account access, welcome, agent contact, referrals and updates
  String get unableToCheckAccess => _isEs
      ? 'No se pudo verificar el acceso a la cuenta.'
      : 'Unable to check account access.';
  String get clientMustCheckBoth => _isEs
      ? 'El cliente o usuario debe marcar las dos casillas obligatorias.'
      : 'The client/user must check both required boxes.';
  String get thisDoesntLookRight =>
      _isEs ? 'Esto no parece correcto' : 'This doesn\'t look right';
  String get pauseConnectionBody => _isEs
      ? 'Esto pausará los mensajes del agente y el intercambio futuro de información. No eliminará su cuenta ni su información. Después puede ingresar el código de agente correcto.'
      : 'This will pause agent messages and future information sharing. It will not delete your account or your information. You can enter the correct agent code afterward.';
  String get goBack => _isEs ? 'Regresar' : 'Go Back';
  String get pauseConnection => _isEs ? 'Pausar conexión' : 'Pause Connection';
  String get recoverPersonalCode => _isEs
      ? 'Recuperar código de acceso personal'
      : 'Recover personal access code';
  String get sendEmail => _isEs ? 'Enviar correo' : 'Send Email';
  String get checkYourEmail =>
      _isEs ? 'Revise su correo electrónico' : 'Check your email';
  String get matchingAccountEmailSent => _isEs
      ? 'Si se encontró una cuenta que coincide, se envió un correo electrónico.'
      : 'If a matching account was found, an email has been sent.';
  String get vitalinkUserAgreement =>
      _isEs ? 'Acuerdo de usuario de VitaLink' : 'VitaLink User Agreement';
  String get thisAgent => _isEs ? 'este agente' : 'this agent';
  String get vitalinkAccess => _isEs ? 'Acceso a VitaLink' : 'VitaLink Access';
  String get vitalinkAccessRequired =>
      _isEs ? 'Se requiere acceso a VitaLink' : 'VitaLink access required';
  String get enterValidAccessCode => _isEs
      ? 'Ingrese un código de agente o un código de acceso personal válido para continuar.'
      : 'Enter a valid agent code or personal access code to continue.';
  String get agentOrPersonalCode => _isEs
      ? 'Código de agente o de acceso personal'
      : 'Agent or personal access code';
  String get checking => _isEs ? 'Verificando...' : 'Checking...';
  String get verifyCode => _isEs ? 'Verificar código' : 'Verify Code';
  String get personalCodesByEmail => _isEs
      ? 'Los códigos de acceso personal se envían por correo electrónico después de emitirse. Revise su bandeja de entrada y la carpeta de correo no deseado, y luego ingrese su código arriba.'
      : 'Personal access codes are delivered by email after they are issued. Check your inbox and spam folder, then enter your code above.';
  String get recoverCodeReceived => _isEs
      ? 'Recuperar un código que ya recibí'
      : 'Recover a code I already received';
  String get handDeviceToClient => _isEs
      ? 'Entregue el dispositivo al cliente o usuario'
      : 'Please hand the device to the client/user';
  String get choicesByClientOnly => _isEs
      ? 'Todas las confirmaciones y opciones de consentimiento a continuación deben completarlas el cliente o usuario, nunca el agente.'
      : 'All confirmations and consent choices below must be completed by the client/user, never by the agent.';
  String get currentClient => _isEs ? 'Cliente actual' : 'Current client';
  String get notClientYet =>
      _isEs ? 'Todavía no soy cliente' : 'Not a client yet';
  String get iAmTheClient => _isEs
      ? 'Soy el cliente o usuario y tomo estas decisiones yo mismo.'
      : 'I am the client/user and I am making these choices myself.';
  String get agreeUserAgreement => _isEs
      ? 'He revisado y acepto el Acuerdo de usuario y la Política de privacidad de VitaLink.'
      : 'I have reviewed and agree to the VitaLink User Agreement and Privacy Policy.';
  String get reviewUserAgreement => _isEs
      ? 'Revisar el Acuerdo de usuario y el Aviso de privacidad'
      : 'Review User Agreement and Privacy Notice';
  String get chooseEitherBothNeither => _isEs
      ? 'Elija una, ambas o ninguna. Estas opciones no lo convierten en cliente y puede cambiarlas después.'
      : 'Choose either, both, or neither. These choices do not make you a client and may be changed later.';
  String get medicareMessages =>
      _isEs ? 'Mensajes de Medicare' : 'Medicare messages';
  String get lifeInsuranceMessages =>
      _isEs ? 'Mensajes de seguro de vida' : 'Life insurance messages';
  String get saving => _isEs ? 'Guardando...' : 'Saving...';
  String get confirmAndContinue =>
      _isEs ? 'Confirmar y continuar' : 'Confirm and Continue';
  String get accountSetup =>
      _isEs ? 'Configuración de la cuenta' : 'Account Setup';
  String get username => _isEs ? 'Nombre de usuario' : 'Username';
  String get enterUsername =>
      _isEs ? 'Ingrese un nombre de usuario' : 'Enter a username';
  String get minSixChars => _isEs ? 'Mínimo 6 caracteres' : 'Min 6 characters';
  String get passwordsDontMatchCurly =>
      _isEs ? 'Las contraseñas no coinciden' : 'Passwords don’t match';
  String get enterYourName => _isEs ? 'Ingrese su nombre' : 'Enter your name';
  String get enterYourPhone =>
      _isEs ? 'Ingrese su teléfono' : 'Enter your phone';
  String get finishSetup => _isEs ? 'Terminar configuración' : 'Finish Setup';
  String get logInAs => _isEs ? 'Iniciar sesión como' : 'Log In As';
  String get continueWithRegistrationCode => _isEs
      ? 'Continuar con el código de registro'
      : 'Continue With Registration Code';
  String get welcomeToVitalink =>
      _isEs ? 'Bienvenido a VitaLink' : 'Welcome to VitaLink';
  String get enterYourEmail =>
      _isEs ? 'Ingrese su correo electrónico' : 'Enter your email';
  String get resetCodeSentCheck => _isEs
      ? 'Se envió el código de restablecimiento a su correo ✅'
      : 'Reset code sent to your email ✅';
  String get requestFailedX =>
      _isEs ? 'La solicitud falló ❌' : 'Request failed ❌';
  String get forgotPasswordBody => _isEs
      ? 'Ingrese su correo electrónico y le enviaremos un código de restablecimiento.'
      : 'Enter your email and we\'ll send you a reset code.';
  String get unableToOpenPhone => _isEs
      ? 'No se pudo abrir la aplicación de teléfono.'
      : 'Unable to open the phone app.';
  String get clientInquirySubject =>
      _isEs ? 'Consulta de cliente de VitaLink' : 'VitaLink Client Inquiry';
  String get unableToOpenEmail => _isEs
      ? 'No se pudo abrir la aplicación de correo.'
      : 'Unable to open the email app.';
  String get unableToOpenDirections => _isEs
      ? 'No se pudieron abrir las indicaciones.'
      : 'Unable to open directions.';
  String get disconnectFromAgentQ =>
      _isEs ? '¿Desconectarse de su agente?' : 'Disconnect from your agent?';
  String get keepMyCurrentAgent =>
      _isEs ? 'Conservar a mi agente actual' : 'Keep My Current Agent';
  String get disconnectAndLock => _isEs
      ? 'Desconectar y bloquear mi cuenta'
      : 'Disconnect and Lock My Account';
  String get unableToDisconnectAgent => _isEs
      ? 'No se pudo desconectar a su agente.'
      : 'Unable to disconnect your agent.';
  String get unableToUpdateConsent => _isEs
      ? 'No se pudo actualizar el consentimiento de mensajes.'
      : 'Unable to update message consent.';
  String get agreeMarketingFromConnected => _isEs
      ? 'Acepto recibir mensajes de mercadeo opcionales dentro de la aplicación y notificaciones de mi agente conectado.'
      : 'I agree to receive optional in-app and push marketing messages from my connected agent.';
  String get iAgree => _isEs ? 'Acepto' : 'I Agree';
  String get noAgentAssigned =>
      _isEs ? 'No hay agente asignado' : 'No Agent Assigned';
  String get call => _isEs ? 'Llamar' : 'Call';
  String get directions => _isEs ? 'Indicaciones' : 'Directions';
  String get scheduleWithMyAgent =>
      _isEs ? 'Programar cita con mi agente' : 'Schedule with My Agent';
  String get reloadInfo => _isEs ? 'Recargar información' : 'Reload Info';
  String get messagesFromMyAgent =>
      _isEs ? 'Mensajes de mi agente' : 'Messages from my agent';
  String get coverageRemindersBody => _isEs
      ? 'Recordatorios de cobertura y avisos de períodos de inscripción. Puede cambiar esto en cualquier momento.'
      : 'Coverage reminders and enrollment-period outreach. You can change this at any time.';
  String get optionalMarketingFromAgent => _isEs
      ? 'Mensajes de mercadeo opcionales dentro de la aplicación y notificaciones de mi agente.'
      : 'Optional in-app and push marketing messages from my agent.';
  String get changeOrDisconnectAgent => _isEs
      ? 'Cambiar o desconectar a mi agente'
      : 'Change or Disconnect My Agent';
  String get sendMyInfoToAgent =>
      _isEs ? 'Enviar mi información al agente' : 'Send My Info to Agent';
  String get referralCenter =>
      _isEs ? 'Centro de referidos' : 'Referral Center';
  String get myInsuranceAgent =>
      _isEs ? 'mi agente de seguros' : 'my insurance agent';
  String get logInBeforeReferral => _isEs
      ? 'Inicie sesión de nuevo antes de enviar un referido.'
      : 'Please log in again before submitting a referral.';
  String get enterReferralNameFirst => _isEs
      ? 'Primero ingrese el nombre de la persona referida.'
      : 'Enter the referral name first.';
  String get enterPhoneForIntro => _isEs
      ? 'Ingrese un número de teléfono para la presentación.'
      : 'Enter a phone number for the introduction.';
  String get introTextOpened => _isEs
      ? 'Se abrió el mensaje de presentación. Envíelo cuando esté listo.'
      : 'Introduction text opened. Send it when ready.';
  String get couldNotOpenText => _isEs
      ? 'No se pudo abrir el mensaje de texto.'
      : 'Could not open text message.';
  String get referralFailed =>
      _isEs ? 'No se pudo enviar el referido.' : 'Referral failed.';
  String get referralCenterBody => _isEs
      ? '¿Conoce a alguien que se beneficiaría de tener organizados sus medicamentos, médicos, tarjetas de seguro e información de emergencia?'
      : 'Know someone who could benefit from keeping their medications, doctors, insurance cards, and emergency information organized?';
  String get sendIntroduction =>
      _isEs ? 'Enviar presentación' : 'Send Introduction';
  String get createTextToReview => _isEs
      ? 'Cree un mensaje de texto que puede revisar y enviar.'
      : 'Create a text message you can review and send.';
  String get createIntroOutsideHousehold => _isEs
      ? 'Cree un mensaje de presentación sencillo para alguien fuera de su hogar.'
      : 'Create a simple introduction text for someone outside your household.';
  String get phoneNumber => _isEs ? 'Número de teléfono' : 'Phone Number';
  String get relationshipOptional =>
      _isEs ? 'Parentesco (opcional)' : 'Relationship Optional';
  String get generateIntroText =>
      _isEs ? 'Generar mensaje de presentación' : 'Generate Introduction Text';
  String get back => _isEs ? 'Atrás' : 'Back';
  String get pleaseSignInAgain =>
      _isEs ? 'Inicie sesión de nuevo.' : 'Please sign in again.';
  String get requestSent => _isEs ? 'Solicitud enviada' : 'Request sent';
  String get unableToSendRequest => _isEs
      ? 'No se pudo enviar su solicitud.'
      : 'Unable to send your request.';
  String get yourAgent => _isEs ? 'Su agente' : 'Your agent';
  String get contactMyAgent =>
      _isEs ? 'Contactar a mi agente' : 'Contact My Agent';
  String get howToBeContacted => _isEs
      ? '¿Cómo prefiere que lo contacten?'
      : 'How would you like to be contacted?';
  String get callMe => _isEs ? 'Llámenme' : 'Call me';
  String get textMe => _isEs ? 'Envíenme un mensaje de texto' : 'Text me';
  String get emailMe => _isEs ? 'Envíenme un correo electrónico' : 'Email me';
  String get sending => _isEs ? 'Enviando...' : 'Sending...';
  String get send => _isEs ? 'Enviar' : 'Send';
  String get vitalinkUpdate =>
      _isEs ? 'Actualización de VitaLink' : 'VitaLink Update';
  String get newUpdateAvailable => _isEs
      ? 'Hay una nueva actualización de VitaLink disponible'
      : 'A New VitaLink Update is Available';
  String get updateIntro => _isEs
      ? 'Mejoramos VitaLink continuamente para que administrar y compartir su información importante sea más fácil y seguro.'
      : 'We’re continually improving VitaLink to make managing and sharing your important information easier and more secure.';
  String get whatsNew => _isEs ? 'Novedades' : 'What\'s New';
  String get updateNew1 => _isEs
      ? 'Mejor rendimiento y confiabilidad'
      : 'Improved performance and reliability';
  String get updateNew2 =>
      _isEs ? 'Notificaciones mejoradas' : 'Enhanced notification support';
  String get updateNew3 => _isEs
      ? 'Mejor vinculación de cuentas y agentes'
      : 'Better account and agent linking';
  String get updateNew4 => _isEs
      ? 'Correcciones de errores y mejoras de estabilidad'
      : 'General bug fixes and stability improvements';
  String get whyUpdate => _isEs ? '¿Por qué actualizar?' : 'Why Update?';
  String get updateWhy1 => _isEs
      ? 'Acceda a las funciones más recientes de VitaLink'
      : 'Access the latest VitaLink features';
  String get updateWhy2 => _isEs
      ? 'Mejore la seguridad y protección de la aplicación'
      : 'Improve app security and protection';
  String get updateWhy3 => _isEs
      ? 'Asegure una mejor compatibilidad con su dispositivo'
      : 'Ensure better device compatibility';
  String get updateWhy4 => _isEs
      ? 'Disfrute de un rendimiento más rápido y confiable'
      : 'Experience faster and more reliable performance';
  String get openAppStore => _isEs ? 'Abrir App Store' : 'Open App Store';
  String get openGooglePlay => _isEs ? 'Abrir Google Play' : 'Open Google Play';
  String get maybeLater => _isEs ? 'Quizás más tarde' : 'Maybe Later';
  String get scanQrCode => _isEs ? 'Escanear código QR' : 'Scan QR Code';
  String get yourAgency => _isEs ? 'su agencia' : 'your agency';
  String get importantAccountUpdate => _isEs
      ? 'Actualización importante de la cuenta'
      : 'Important Account Update';
  String get callAgency => _isEs ? 'Llamar a la agencia' : 'Call Agency';
  String get emergencyProfilesEncrypted => _isEs
      ? 'Los perfiles de emergencia están cifrados y guardados de forma segura para acceder con el código QR en emergencias.'
      : 'Emergency profiles are encrypted and securely stored for QR access in emergencies.';
  String get tapForInfo =>
      _isEs ? 'TOQUE PARA VER INFORMACIÓN' : 'TAP FOR INFO';
  String isAgentYourCurrent(String agent) => _isEs
      ? '¿$agent es su agente de seguros actual?'
      : 'Is $agent your current insurance agent?';
  String agentMessagingConsent(String agent) => _isEs
      ? 'Acepto recibir mensajes dentro de la aplicación y notificaciones de $agent, agente de seguros con licencia, incluidos recordatorios de cobertura y avisos de períodos de inscripción. Entiendo que el agente puede recibir una compensación si me inscribo en un plan. Este consentimiento es opcional y puedo retirarlo. Deje esta casilla sin marcar para decidir más tarde.'
      : 'I agree to receive in-app and push messages from $agent, a licensed insurance agent, including coverage reminders and enrollment-period outreach. I understand the agent may be compensated if I enroll in a plan. This consent is optional and may be withdrawn. Leave this unchecked to decide later.';
  String optionalMessagesFrom(String agent) =>
      _isEs ? 'Mensajes opcionales de $agent' : 'Optional messages from $agent';
  String agreeMedicareMessagesFrom(String agent) => _isEs
      ? 'Acepto recibir mensajes opcionales de Medicare dentro de la aplicación y notificaciones de $agent.'
      : 'I agree to receive optional in-app and push Medicare messages from $agent.';
  String agreeLifeMessagesFrom(String agent) => _isEs
      ? 'Acepto recibir mensajes opcionales de seguro de vida dentro de la aplicación y notificaciones de $agent.'
      : 'I agree to receive optional in-app and push life insurance messages from $agent.';
  String activationCodeIntro() => _isEs
      ? 'Las cuentas de cliente de VitaLink requieren un código de acceso antes del registro. Este código puede venir de su agente de seguros o enviarse por correo electrónico después de emitirse.\n\n¿Ya tiene un código de activación de VitaLink?'
      : 'VitaLink client accounts require an access code before registration. This code may come from your insurance agent or be delivered by email after it is issued.\n\nDo you already have a VitaLink activation code?';
  String disconnectAgentBody() => _isEs
      ? 'Al desconectarse de su agente terminará su acceso patrocinado a VitaLink. Para seguir usando VitaLink, necesitará el código de otro agente o un código de acceso personal.\n\nLos mensajes del agente y el intercambio futuro de información se detendrán. La información ya guardada en este dispositivo no se eliminará.'
      : 'Disconnecting from your agent will end your sponsored VitaLink access. To continue using VitaLink, you will need another agent\'s code or a personal access code.\n\nAgent messaging and future information sharing will stop. Information already stored on this device will not be deleted.';
  String myAgentNamed(String agent) =>
      _isEs ? 'mi agente, $agent' : 'my agent, $agent';
  String referralIntroMessage(String name, String agent, String link) => _isEs
      ? 'Hola $name:\n\nHace poco empecé a usar VitaLink para tener mis medicamentos, médicos, tarjetas de seguro, citas e información de emergencia en un solo lugar.\n\nLo que más me sorprendió fue lo útil que sería si alguna vez hubiera una emergencia y mi familia necesitara acceder a información importante.\n\nMientras más lo usaba, más me daba cuenta de cuántas personas podrían beneficiarse de algo así, y enseguida pensé en ti.\n\nSi quieres saber un poco más, con gusto te pongo en contacto con $agent, quien me ayudó a configurarlo todo.\n\n¿Te parece bien que se comunique contigo? Si es así, ¿prefieres un mensaje de texto, una llamada o un correo electrónico?\n\nToca aquí para saber más:\n$link'
      : 'Hey $name,\n\nI recently started using VitaLink to keep my medications, doctors, insurance cards, appointments, and emergency information all in one place.\n\nWhat surprised me most was how useful it would be if there was ever an emergency and my family needed access to important information.\n\nThe more I used it, the more I realized how many people could benefit from having something like this, and I immediately thought of you.\n\nIf you\'d like to learn a little more about it, I\'d be happy to connect you with $agent, who helped me get everything set up.\n\nWould it be okay if I had them reach out to you? If so, would you prefer a text message, phone call, or email?\n\nTap here to learn more:\n$link';
  String agentHasBeenNotified(String agent) =>
      _isEs ? 'Se notificó a $agent.' : '$agent has been notified.';
  String agentWouldLikeToHelp(String agent, String topic) => _isEs
      ? 'A $agent le gustaría ayudarle con $topic.'
      : '$agent would like to help with $topic.';
  String agentMayContactAbout(String agent, String topic) => _isEs
      ? '$agent puede contactarme sobre $topic por los medios que seleccioné.'
      : '$agent may contact me about $topic using the methods I selected.';
  String agentInactiveBody(String agency, String phone) => _isEs
      ? 'Su agente de seguros ya no está activo.\n\nComuníquese con $agency al $phone para recibir ayuda.'
      : 'Your insurance agent is no longer active.\n\nPlease contact $agency at $phone for assistance.';
  String agentInactiveBodyNoPhone(String agency) => _isEs
      ? 'Su agente de seguros ya no está activo.\n\nComuníquese con $agency para recibir ayuda.'
      : 'Your insurance agent is no longer active.\n\nPlease contact $agency for assistance.';
  String welcomeName(String name) =>
      _isEs ? 'Bienvenido, $name' : 'Welcome, $name';

  // User terms
  String get declineTerms => _isEs ? 'Rechazar los términos' : 'Decline Terms';
  String get declineTermsBody => _isEs
      ? 'Si no acepta los términos, no puede usar VitaLink.'
      : 'If you do not accept the terms, you cannot use VitaLink.';
  String get exitApp => _isEs ? 'Salir de la aplicación' : 'Exit App';
  String get mustAcceptTerms => _isEs
      ? 'Debe aceptar los términos para continuar.'
      : 'You must accept the terms to continue.';
  String get userTermsOfService =>
      _isEs ? 'Términos de servicio para usuarios' : 'User Terms of Service';
  String get decline => _isEs ? 'Rechazar' : 'Decline';
  String get accept => _isEs ? 'Aceptar' : 'Accept';

  // Agent login, menu, registration and setup
  String get agentPortalNotActive => _isEs
      ? 'Su acceso al portal de agentes no está activo. Comuníquese con el soporte de VitaLink antes de iniciar sesión.'
      : 'Your agent portal access is not active. Contact VitaLink support before logging in.';
  String get invalidResponse =>
      _isEs ? 'Respuesta no válida' : 'Invalid response';
  String get loginError => _isEs ? 'Error al iniciar sesión' : 'Login error';
  String get agentEmail =>
      _isEs ? 'Correo electrónico del agente' : 'Agent Email';
  String get loginAsAgent =>
      _isEs ? 'Iniciar sesión como agente' : 'Login as Agent';
  String get accessNotActive =>
      _isEs ? 'Acceso no activo' : 'Access Not Active';
  String get agentAgreementUpdate =>
      _isEs ? 'Actualización del acuerdo de agente' : 'Agent Agreement Update';
  String get agentResponsibilitiesBody => _isEs
      ? 'Usted es el único responsable de cumplir las reglas de mercadeo de CMS y estatales que correspondan. Las confirmaciones de la relación con el cliente y el consentimiento para mensajes siempre deben completarlos el cliente o usuario, nunca el agente. Los mensajes solo se permiten para clientes confirmados con consentimiento activo. VitaLink guarda un registro de auditoría de estas acciones.'
      : 'You are solely responsible for compliance with applicable CMS and state marketing rules. Client relationship confirmations and messaging consent must always be completed by the client/user, never by the agent. Messaging is allowed only for confirmed clients with active consent. VitaLink records an audit trail of these actions.';
  String get agreeAgentResponsibilities => _isEs
      ? 'Entiendo y acepto estas responsabilidades de agente.'
      : 'I understand and agree to these agent responsibilities.';
  String get agentNotificationsNeeded => _isEs
      ? 'VitaLink necesita las notificaciones activadas para que reciba alertas de referidos, actualizaciones de perfil y mensajes de clientes.'
      : 'VitaLink needs notifications turned on so you can receive referral alerts, profile updates, and client messages.';
  String get agentCodeNeeded =>
      _isEs ? 'Se necesita el código de agente' : 'Agent Code Needed';
  String get couldntLoadAgentCode => _isEs
      ? 'No pudimos cargar su código de agente. Abra Mi agente una vez y vuelva a intentarlo.'
      : 'We couldn\'t load your agent code. Open My Agent once, then try again.';
  String get businessCardScanner =>
      _isEs ? 'Escáner de tarjetas de presentación' : 'Business Card Scanner';
  String get myClients => _isEs ? 'Mis clientes' : 'My Clients';
  String get notesTasks => _isEs ? 'Notas / Tareas' : 'Notes / Tasks';
  String get registerUserAccount =>
      _isEs ? 'Registrar cuenta de usuario' : 'Register User Account';
  String get tenCharsMin => _isEs ? '≥ 10 caracteres' : '≥ 10 characters';
  String get atLeastOneUppercase =>
      _isEs ? 'Al menos 1 mayúscula' : 'At least 1 uppercase';
  String get agentAccessNotActive =>
      _isEs ? 'Acceso de agente no activo' : 'Agent Access Not Active';
  String get agentAccountNotActive => _isEs
      ? 'Esta cuenta de agente no está activa. Comuníquese con el soporte de VitaLink antes de iniciar sesión.'
      : 'This agent account is not active. Contact VitaLink support before logging in.';
  String get registrationFailedTitle =>
      _isEs ? 'No se pudo completar el registro' : 'Registration Failed';
  String get unknownErrorX => _isEs ? 'Error desconocido ❌' : 'Unknown error ❌';
  String get error => _isEs ? 'Error' : 'Error';
  String get agentRegistration =>
      _isEs ? 'Registro de agente' : 'Agent Registration';
  String get enterYourNpn => _isEs ? 'Ingrese su NPN' : 'Enter your NPN';
  String get enterYourPhoneNumber =>
      _isEs ? 'Ingrese su número de teléfono' : 'Enter your phone number';
  String get enterAgencyName =>
      _isEs ? 'Ingrese el nombre de su agencia' : 'Enter your agency name';
  String get agencyStreetAddress =>
      _isEs ? 'Dirección de la agencia' : 'Agency Street Address';
  String get enterAgencyAddress => _isEs
      ? 'Ingrese la dirección de su agencia'
      : 'Enter your agency address';
  String get agencyCity => _isEs ? 'Ciudad de la agencia' : 'Agency City';
  String get enterAgencyCity =>
      _isEs ? 'Ingrese la ciudad de su agencia' : 'Enter your agency city';
  String get passwordRulesHelper => _isEs
      ? '≥ 10 caracteres • 1 mayúscula • 1 carácter especial'
      : '≥ 10 characters • 1 uppercase • 1 special character';
  String get agentRegistrationCode =>
      _isEs ? 'Código de registro de agente' : 'Agent Registration Code';
  String get enterAgentRegistrationCodeField => _isEs
      ? 'Ingrese el código de registro de agente'
      : 'Enter agent registration code';
  String get resetCodeSentCheckShort =>
      _isEs ? 'Código de restablecimiento enviado ✅' : 'Reset code sent ✅';
  String get agentRequestReset =>
      _isEs ? 'Solicitar restablecimiento (agente)' : 'Agent Request Reset';
  String get agentPasswordReset => _isEs
      ? 'La contraseña del agente se restableció correctamente.'
      : 'Agent password has been reset successfully.';
  String get agentResetPassword =>
      _isEs ? 'Restablecer contraseña de agente' : 'Agent Reset Password';
  String get agentPortalTitle =>
      _isEs ? 'Portal de agentes de VitaLink' : 'VitaLink Agent Portal';
  String get agentProfile => _isEs ? 'Perfil del agente' : 'Agent Profile';
  String get agency => _isEs ? 'Agencia' : 'Agency';
  String get agencyPhoneNumber =>
      _isEs ? 'Teléfono de la agencia' : 'Agency Phone Number';
  String get streetAddress => _isEs ? 'Dirección' : 'Street Address';
  String get npnLicense => _isEs ? 'NPN / N.º de licencia' : 'NPN / License #';
  String get updatePasswordOptional =>
      _isEs ? 'Actualizar contraseña (opcional)' : 'Update Password (optional)';
  String get saveProfile => _isEs ? 'Guardar perfil' : 'Save Profile';
  String welcomeAgent(String name) =>
      _isEs ? 'Bienvenido, $name' : 'Welcome $name';
  String registrationFailedError(String error) => _isEs
      ? 'No se pudo completar el registro: $error'
      : 'Registration failed: $error';

  // Agent clients, notes, referrals, agent profile and agent terms
  String get missingAgentSession =>
      _isEs ? 'Falta la sesión del agente' : 'Missing agent session';
  String get invalidAgentId =>
      _isEs ? 'ID de agente no válido' : 'Invalid agent ID';
  String get failedToLoadClients =>
      _isEs ? 'No se pudieron cargar los clientes' : 'Failed to load clients';
  String get noClientsFound =>
      _isEs ? 'No se encontraron clientes' : 'No clients found';
  String get activeLabel => _isEs ? 'Activo' : 'Active';
  String get inactiveLabel => _isEs ? 'Inactivo' : 'Inactive';
  String get failedToLoadNotes => _isEs
      ? 'No se pudieron cargar las notas y tareas'
      : 'Failed to load notes and tasks';
  String get failedToLoadSavedItems => _isEs
      ? 'No se pudieron cargar los elementos guardados'
      : 'Failed to load saved items';
  String get chooseClientFirst =>
      _isEs ? 'Primero elija un cliente' : 'Choose a client first';
  String get addNoteTextFirst => _isEs
      ? 'Primero escriba el texto de la nota o tarea'
      : 'Add note or task text first';
  String get noteSaved => _isEs ? 'Nota guardada' : 'Note saved';
  String get taskSaved => _isEs ? 'Tarea guardada' : 'Task saved';
  String get failedToSave => _isEs ? 'No se pudo guardar' : 'Failed to save';
  String get couldNotDeleteItem => _isEs
      ? 'No se pudo eliminar este elemento'
      : 'Could not delete this item';
  String get removeFromAppAndCrm => _isEs
      ? 'Esto lo eliminará de la aplicación y del CRM.'
      : 'This will remove it from the app and CRM.';
  String get taskDeleted => _isEs ? 'Tarea eliminada' : 'Task deleted';
  String get noteDeleted => _isEs ? 'Nota eliminada' : 'Note deleted';
  String get failedToDelete =>
      _isEs ? 'No se pudo eliminar' : 'Failed to delete';
  String get micPermissionNeeded => _isEs
      ? 'Se necesita permiso del micrófono para dictar'
      : 'Microphone permission is needed for dictation';
  String get dictationNotAvailable => _isEs
      ? 'El dictado por voz no está disponible en este dispositivo'
      : 'Voice dictation is not available on this device';
  String get clientLabel => _isEs ? 'Cliente' : 'Client';
  String get noteLabel => _isEs ? 'Nota' : 'Note';
  String get taskLabel => _isEs ? 'Tarea' : 'Task';
  String get enterNote => _isEs ? 'Escriba una nota...' : 'Enter note...';
  String get enterTask => _isEs ? 'Escriba una tarea...' : 'Enter task...';
  String get noSavedNotes =>
      _isEs ? 'No hay notas ni tareas guardadas' : 'No saved notes or tasks';
  String get logInBeforeViewingReferrals => _isEs
      ? 'Inicie sesión de nuevo antes de ver los referidos.'
      : 'Please log in again before viewing referrals.';
  String get failedToLoadReferrals => _isEs
      ? 'No se pudieron cargar los referidos.'
      : 'Failed to load referrals.';
  String get updateFailedDot =>
      _isEs ? 'No se pudo actualizar.' : 'Update failed.';
  String get thisReferral => _isEs ? 'este referido' : 'this referral';
  String get deleteReferralQ =>
      _isEs ? '¿Eliminar referido?' : 'Delete Referral?';
  String get referralDeleted =>
      _isEs ? 'Referido eliminado.' : 'Referral deleted.';
  String get deleteFailed => _isEs ? 'No se pudo eliminar.' : 'Delete failed.';
  String get noReferralsYet =>
      _isEs ? 'Aún no hay referidos.' : 'No referrals yet.';
  String get metricActivity => _isEs ? 'Actividad' : 'Activity';
  String get metricLeads => _isEs ? 'Prospectos' : 'Leads';
  String get metricIntroductions => _isEs ? 'Presentaciones' : 'Introductions';
  String get metricContact => _isEs ? 'Contacto' : 'Contact';
  String get metricConversion => _isEs ? 'Conversión' : 'Conversion';
  String get referralWord => _isEs ? 'Referido' : 'Referral';
  String get requestType => _isEs ? 'Tipo de solicitud' : 'Request Type';
  String get prospectRequest =>
      _isEs ? 'Solicitud de posible cliente' : 'Prospect request';
  String get topicLabel => _isEs ? 'Tema' : 'Topic';
  String get preferredContact =>
      _isEs ? 'Contacto preferido' : 'Preferred Contact';
  String get referredBy => _isEs ? 'Referido por' : 'Referred By';
  String get received => _isEs ? 'Recibido' : 'Received';
  String get linkOpened => _isEs ? 'Enlace abierto' : 'Link Opened';
  String get preferenceSubmitted =>
      _isEs ? 'Preferencia enviada' : 'Preference Submitted';
  String get contacted => _isEs ? 'Contactado' : 'Contacted';
  String get statusLabel => _isEs ? 'Estado' : 'Status';
  String get markContacted =>
      _isEs ? 'Marcar como contactado' : 'Mark Contacted';
  String get deleteReferral => _isEs ? 'Eliminar referido' : 'Delete Referral';
  String get inviteLinkCopied =>
      _isEs ? 'Enlace de invitación copiado' : 'Invite link copied';
  String get notificationResults =>
      _isEs ? 'Resultados de la notificación' : 'Notification Results';
  String get unknownError => _isEs ? 'Error desconocido' : 'Unknown error';
  String get tplMedicareAepTitle =>
      _isEs ? 'Medicare: recordatorio del AEP' : 'Medicare: AEP reminder';
  String get tplMedicareAepPreview => _isEs
      ? 'El AEP comienza el 15 de octubre. ¿Desea programar una revisión de su cobertura de Medicare?'
      : 'AEP begins October 15. Would you like to schedule a Medicare coverage review?';
  String get tplMedicareWindowTitle => _isEs
      ? 'Medicare: período de inscripción'
      : 'Medicare: Enrollment window';
  String get tplMedicareWindowPreview => _isEs
      ? 'Se acerca su período de inscripción en Medicare. ¿Desea que me comunique con usted?'
      : 'Your Medicare enrollment window is approaching. Would you like me to reach out?';
  String get tplMedicareOptionsTitle =>
      _isEs ? 'Medicare: hablar de opciones' : 'Medicare: Talk about options';
  String get tplMedicareOptionsPreview => _isEs
      ? '¿Desea hablar sobre sus opciones de Medicare?'
      : 'Would you like to talk about your Medicare options?';
  String get tplLifeAwarenessTitle =>
      _isEs ? 'Vida: mes de concientización' : 'Life: Awareness Month';
  String get tplLifeAwarenessPreview => _isEs
      ? 'Es el mes de concientización sobre el seguro de vida. ¿Desea que hablemos?'
      : 'It\'s Life Insurance Awareness Month. Would you like to talk?';
  String get tplLifeFamilyTitle =>
      _isEs ? 'Vida: usted o su familia' : 'Life: You or your family';
  String get tplLifeFamilyPreview => _isEs
      ? '¿Desea hablar sobre opciones de seguro de vida para usted o su familia?'
      : 'Would you like to discuss life insurance options for you or your family?';
  String get sendProspectMessage => _isEs
      ? 'Enviar un mensaje a posibles clientes'
      : 'Send a prospect message';
  String get messageResults =>
      _isEs ? 'Resultados del mensaje' : 'Message results';
  String get unableToSend => _isEs ? 'No se pudo enviar' : 'Unable to send';
  String get messageCouldNotSend => _isEs
      ? 'No se pudo enviar el mensaje.'
      : 'The message could not be sent.';
  String get copyInviteLink =>
      _isEs ? 'Copiar enlace de invitación' : 'Copy Invite Link';
  String get scanBusinessCard =>
      _isEs ? 'Escanear tarjeta de presentación' : 'Scan Business Card';
  String get sendMyInformation =>
      _isEs ? 'Enviar mi información' : 'Send My Information';
  String get sendClientMedicareNotification => _isEs
      ? 'Enviar notificación de Medicare a clientes'
      : 'Send Client Medicare Notification';
  String get sendProspectMessageButton =>
      _isEs ? 'Enviar mensaje a posibles clientes' : 'Send Prospect Message';
  String get agentEmailRequiredScan => _isEs
      ? 'Se requiere el correo electrónico del agente antes de escanear.'
      : 'Agent email is required before scanning.';
  String get businessCardScanFailed => _isEs
      ? 'No se pudo escanear la tarjeta de presentación'
      : 'Business card scan failed';
  String get noBusinessCardDetails => _isEs
      ? 'No se encontraron datos en la tarjeta de presentación'
      : 'No business card details found';
  String get reviewBusinessCard =>
      _isEs ? 'Revisar tarjeta de presentación' : 'Review Business Card';
  String get addressLabel => _isEs ? 'Dirección' : 'Address';
  String get apply => _isEs ? 'Aplicar' : 'Apply';
  String get oneUppercaseRequired =>
      _isEs ? 'Se requiere 1 mayúscula' : '1 uppercase required';
  String get oneSpecialRequired => _isEs
      ? 'Se requiere 1 carácter especial'
      : '1 special character required';
  String get updateFailed => _isEs ? 'No se pudo actualizar' : 'Update failed';
  String get agentProfileUpdated =>
      _isEs ? 'Perfil del agente actualizado ✅' : 'Agent profile updated ✅';
  String get myAgentProfile =>
      _isEs ? 'Mi perfil de agente' : 'My Agent Profile';
  String get emailCannotChange => _isEs
      ? 'Correo electrónico (no se puede cambiar)'
      : 'Email (cannot be changed)';
  String get scanningBusinessCard => _isEs
      ? 'Escaneando tarjeta de presentación...'
      : 'Scanning Business Card...';
  String get calendlyLink => _isEs ? 'Enlace de Calendly' : 'Calendly Link';
  String get enterValidLink =>
      _isEs ? 'Ingrese un enlace válido' : 'Enter a valid link';
  String get changePasswordOptional =>
      _isEs ? 'Cambiar contraseña (opcional)' : 'Change Password (optional)';
  String get declineAgentTermsBody => _isEs
      ? 'Si no acepta los términos, no puede usar VitaLink (Agente).'
      : 'If you do not accept the terms, you cannot use VitaLink (Agent).';
  String get agentTermsOfService =>
      _isEs ? 'Términos de servicio para agentes' : 'Agent Terms of Service';
  String get agentTermsClosing => _isEs
      ? 'Si no acepta estos términos, no puede usar la aplicación como agente.'
      : 'If you do not agree to these terms, you cannot use the app as an Agent.';
  String deviceYesNo(bool hasDevice) => _isEs
      ? 'Dispositivo: ${hasDevice ? 'SÍ' : 'NO'}'
      : 'Device: ${hasDevice ? 'YES' : 'NO'}';
  String deleteNoteOrTaskQ(bool isTask) => _isEs
      ? '¿Eliminar ${isTask ? 'tarea' : 'nota'}?'
      : 'Delete ${isTask ? 'task' : 'note'}?';
  String removeReferralBody(String name) => _isEs
      ? '¿Quitar a $name de su lista de referidos? Esto solo elimina el registro del referido de su pantalla de agente.'
      : 'Remove $name from your referral list? This only removes the referral record from your agent screen.';
  String campaignValue(String campaign) =>
      _isEs ? 'Campaña: $campaign' : 'Campaign: $campaign';
  String devicesTargeted(Object total) =>
      _isEs ? 'Dispositivos objetivo: $total' : 'Devices targeted: $total';
  String usersNotified(Object count) =>
      _isEs ? 'Usuarios notificados: $count' : 'Users notified: $count';
  String failuresCount(Object count) =>
      _isEs ? 'Fallas: $count' : 'Failures: $count';
  String prospectDevicesNotified(Object count) => _isEs
      ? 'Se notificó a $count dispositivo(s) de posibles clientes.'
      : '$count prospect device(s) notified.';
  String agencyValue(String value) =>
      _isEs ? 'Agencia: $value' : 'Agency: $value';
  String addressValue(String value) =>
      _isEs ? 'Dirección: $value' : 'Address: $value';
  String phoneValue(String value) =>
      _isEs ? 'Teléfono: $value' : 'Phone: $value';
  String myAgentTitle(String name) =>
      _isEs ? 'Mi agente: $name' : 'My Agent - $name';
  String businessCardScanFailedError(String error) => _isEs
      ? 'No se pudo escanear la tarjeta de presentación: $error'
      : 'Business card scan failed: $error';
  String cardEmailFound(String email) => _isEs
      ? 'Correo encontrado en la tarjeta: $email'
      : 'Card email found: $email';
  String logoDetected() => _isEs
      ? 'Se detectó un logotipo en la tarjeta.'
      : 'Logo detected on card.';
  String headshotDetected() => _isEs
      ? 'Se detectó una foto en la tarjeta.'
      : 'Headshot detected on card.';
  String agentTermsBody() => _isEs
      ? 'Bienvenido a VitaLink (Agente).\n\nAl usar esta aplicación como agente, usted acepta lo siguiente:\n• Debe mantener una licencia válida para ofrecer servicios de Medicare.\n• Usted es el único responsable de cumplir las pautas de CMS y AHIP.\n• Debe proteger los datos de los clientes y nunca compartir sus credenciales de inicio de sesión.\n• Nunca debe aceptar un Acuerdo de usuario, una confirmación de relación ni un consentimiento para mensajes en nombre de un cliente. El cliente o usuario debe tomar cada decisión de consentimiento en su propio dispositivo.\n• Solo puede enviar mensajes a clientes confirmados con consentimiento activo. Los posibles clientes y los cuidadores no pueden recibir mensajes del agente.\n• Usted es responsable de cada declaración sobre el estado de un cliente y de cada mensaje enviado desde su cuenta. VitaLink puede conservar un registro de auditoría de estas acciones.\n• Acepta que el uso indebido puede resultar en la cancelación inmediata del acceso.\n\nResponsabilidad y cumplimiento del agente\n\n• Usted es responsable de que toda la información de clientes que ingrese o comparta sea exacta y esté actualizada.\n• Debe manejar todos los datos de clientes de acuerdo con los requisitos de privacidad, seguridad y regulatorios que correspondan.\n• VitaLink no verifica ni valida los datos que ingresan los agentes o los usuarios.\n\nDescargo de responsabilidad médica y legal\n\n• VitaLink es solamente una herramienta para guardar y compartir datos y no verifica, valida ni garantiza la exactitud, integridad ni vigencia de ninguna información.\n• VitaLink no es un proveedor médico, una aseguradora ni un servicio de asesoría con licencia.\n• La aplicación no ofrece consejos médicos, diagnósticos ni recomendaciones de tratamiento.\n• Los agentes y usuarios no deben depender únicamente de esta aplicación para tomar decisiones de salud o de emergencia.\n• VitaLink no es responsable de errores, omisiones ni información desactualizada contenida en la aplicación.\n\nActivación y acceso de clientes\n\nLos agentes pueden dar códigos de activación a sus clientes para que accedan al servicio de VitaLink.\n\nLos clientes de agentes participantes recibirán un código de activación de su agente.\n\nLos agentes son responsables de que toda la información de clientes ingresada en la aplicación sea exacta y se maneje de acuerdo con los requisitos de privacidad y regulatorios que correspondan.\n\nPara ver los Términos de servicio y la Política de privacidad completos, visite:\n'
      : 'Welcome to VitaLink (Agent).\n\nBy using this app as an Agent, you agree:\n• You must maintain a valid license to offer Medicare services.\n• You are solely responsible for compliance with CMS and AHIP guidelines.\n• You must safeguard client data and never share login credentials.\n• You must never accept a User Agreement, relationship confirmation, or messaging consent for a client. The client/user must make every consent choice on their own device.\n• You may send messages only to confirmed clients with active consent. Prospects and caregivers are not eligible for agent messaging.\n• You are responsible for every client-status assertion and message sent through your account. VitaLink may retain an audit trail of these actions.\n• You agree that misuse may result in immediate access termination.\n\nAgent Responsibility & Compliance\n\n• You are responsible for ensuring all client information entered or shared is accurate and up to date.\n• You must handle all client data in accordance with applicable privacy, security, and regulatory requirements.\n• VitaLink does not verify or validate any data entered by agents or users.\n\nMedical & Liability Disclaimer\n\n• VitaLink is a data storage and sharing tool only and does not verify, validate, or guarantee the accuracy, completeness, or timeliness of any information.\n• VitaLink is not a medical provider, insurer, or licensed advisory service.\n• The app does not provide medical advice, diagnosis, or treatment recommendations.\n• Agents and users must not rely solely on this app for healthcare or emergency decisions.\n• VitaLink is not liable for errors, omissions, or outdated information contained within the app.\n\nActivation & Client Access\n\nAgents may provide activation codes to their clients for access to the VitaLink service.\n\nClients of participating agents will receive an activation code from their agent.\n\nAgents are responsible for ensuring that any client information entered into the app is accurate and handled in accordance with applicable privacy and regulatory requirements.\n\nFor full Terms of Service and Privacy Policy, visit:\n';

  // Leftovers across screens
  String get vaDirectory => _isEs ? 'Directorio de VA' : 'VA directory';
  String get almostReady => _isEs ? '¡Ya casi!' : 'Almost ready!';
  String get confirmMedsDoctorsBeforeSigning => _isEs
      ? 'Antes de firmar, confirme que sus medicamentos y médicos estén al día. Su agente usa esta información para ayudarle a encontrar la mejor cobertura.'
      : 'Before signing, please confirm your medications and doctors are current. Your agent uses this to help find you the best coverage.';
  String get letMeUpdateFirst =>
      _isEs ? 'Primero quiero actualizar' : 'Let me update first';
  String get everythingLooksGood =>
      _isEs ? 'Todo está bien' : 'Everything looks good';
  String get noProblem => _isEs ? '¡No hay problema!' : 'No problem!';
  String get reviewThenComeBack => _isEs
      ? 'Revise sus medicamentos y médicos, y regrese a firmar cuando todo esté correcto.'
      : 'Review your medications and doctors, then come back to sign when everything looks right.';
  String get reviewMyInfo =>
      _isEs ? 'Revisar mi información' : 'Review my info';
  String get vitalinkHome => _isEs ? 'Inicio de VitaLink' : 'VitaLink Home';
  String get tapLogoToOpenMenu =>
      _isEs ? 'Toque el logotipo para abrir el menú' : 'Tap logo to open menu';
  String get emergencyInfo911 =>
      _isEs ? 'Información de emergencia 911' : '911 Emergency Info';
  String get openMenu => _isEs ? 'Abrir menú' : 'Open Menu';
  String get registrationReturnedNoUser => _isEs
      ? 'El registro no devolvió un usuario'
      : 'Registration returned no user';
  String get prefilledFromAgentAccount => _isEs
      ? 'Completamos esto con los datos de su cuenta de agente. Agregue su dirección personal y luego complete el registro.'
      : 'We filled this in from your agent account. Add your personal address, then complete registration.';
  String get yourConnectionCaps => _isEs ? 'SU CONEXIÓN' : 'YOUR CONNECTION';
  String get connectionHelpsPermissions => _isEs
      ? 'Esto ayuda a VitaLink a aplicar los permisos de comunicación correctos. El cliente o usuario lo confirmará después del registro.'
      : 'This helps VitaLink apply the correct communication permissions. The client/user will confirm this after registration.';
  String get guest => _isEs ? 'Invitado' : 'Guest';
  String get updateVitalink =>
      _isEs ? 'Actualizar VitaLink' : 'Update VitaLink';
  String get remindMeLater =>
      _isEs ? 'Recordármelo más tarde' : 'Remind me later';
  String get signatureImageMissing =>
      _isEs ? 'Falta la imagen de la firma' : 'Signature image missing';
  String vitalinkHomeFor(String name) =>
      _isEs ? 'Inicio de VitaLink de $name' : 'VitaLink Home for $name';
  // ---- generated: end ----
}
