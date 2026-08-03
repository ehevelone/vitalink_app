import 'package:flutter/widgets.dart';

class AppStrings {
  final String languageCode;

  const AppStrings(this.languageCode);

  static AppStrings of(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return AppStrings(code == 'es' ? 'es' : 'en');
  }

  bool get _es => languageCode == 'es';

  String get settings => _es ? 'Configuracion' : 'Settings';
  String get language => _es ? 'Idioma' : 'Language';
  String get chooseDisplayLanguage => _es
      ? 'Elija el idioma de visualizacion de VitaLink.'
      : 'Choose the display language for VitaLink.';
  String get displayLanguage =>
      _es ? 'Idioma de visualizacion' : 'Display Language';
  String get languageSaved =>
      _es ? 'Preferencia de idioma guardada.' : 'Language preference saved.';
  String get usePhoneLanguage =>
      _es ? 'Usar idioma del telefono' : 'Use phone language';
  String get english => _es ? 'Ingles' : 'English';
  String get spanish => _es ? 'Espanol' : 'Spanish';

  String welcome(String name) => _es ? 'Bienvenido $name' : 'Welcome $name';
  String get user => _es ? 'Usuario' : 'User';
  String get newNotification => _es ? 'Nueva notificacion' : 'New Notification';
  String get newNotificationBody =>
      _es ? 'Tiene una nueva notificacion' : 'You have a new notification';
  String get ok => _es ? 'OK' : 'OK';
  String get later => _es ? 'Mas tarde' : 'Later';
  String get allowNotifications =>
      _es ? 'Permitir notificaciones' : 'Allow Notifications';
  String get notificationsNeeded => _es
      ? 'VitaLink necesita que las notificaciones esten activadas para que pueda recibir alertas importantes, actualizaciones de perfil y mensajes de su agente.'
      : 'VitaLink needs notifications turned on so you can receive important alerts, profile updates, and messages from your agent.';
  String get openSettings => _es ? 'Abrir configuracion' : 'Open Settings';

  String get myAgent => _es ? 'Mi agente' : 'My Agent';
  String get medications => _es ? 'Medicamentos' : 'Medications';
  String get doctors => _es ? 'Doctores' : 'Doctors';
  String get appointments => _es ? 'Citas' : 'Appointments';
  String get insuranceCards => _es ? 'Tarjetas de seguro' : 'Insurance Cards';
  String get insurancePolicies =>
      _es ? 'Polizas de seguro' : 'Insurance Policies';
  String get myProfile => _es ? 'Mi perfil' : 'My Profile';
  String get profileSharing => _es ? 'Compartir perfil' : 'Profile Sharing';
  String get profileUpdates =>
      _es ? 'Actualizaciones de perfil' : 'Profile Updates';
  String get addFamilyMember => _es ? 'Agregar familiar' : 'Add Family Member';
  String get switchProfile => _es ? 'Cambiar perfil' : 'Switch Profile';
  String get emergencyInfo =>
      _es ? 'Informacion de emergencia' : 'Emergency Info';
  String get logOut => _es ? 'Cerrar sesion' : 'Log Out';
  String get logIn => _es ? 'Iniciar sesion' : 'Log In';
  String get agentLogin => _es ? 'Inicio de agente' : 'Agent Login';
  String get createAccount => _es ? 'Crear cuenta' : 'Create Account';
  String get chooseAccountType => _es
      ? 'Elija el tipo de cuenta que coincide con como usa VitaLink.'
      : 'Choose the account type that matches how you use VitaLink.';
  String get createClientAccount =>
      _es ? 'Crear cuenta de cliente' : 'Create Client Account';
  String get forUsersAndFamilies => _es
      ? 'Para usuarios y familias de VitaLink'
      : 'For VitaLink users and families';
  String get activateAgentPortal =>
      _es ? 'Activar portal de agente' : 'Activate Agent Portal';
  String get agentActivationSubtitle => _es
      ? 'Los agentes de seguros deben activar el acceso en myvitalink.app'
      : 'Insurance agents must activate access through myvitalink.app';
  String get clientAccountActivation =>
      _es ? 'Activacion de cuenta de cliente' : 'Client Account Activation';
  String get clientActivationBody => _es
      ? 'Las cuentas de cliente de VitaLink requieren un codigo de activacion antes del registro. Este codigo puede venir de su agente de seguros o de myvitalink.app.\n\nYa tiene un codigo de activacion de VitaLink?'
      : 'VitaLink client accounts require an activation code before registration. This code may come from your insurance agent or from myvitalink.app.\n\nDo you already have a VitaLink activation code?';
  String get iHaveCode => _es ? 'Tengo un codigo' : 'I Have a Code';
  String get getActivationCode =>
      _es ? 'Obtener codigo de activacion' : 'Get Activation Code';
  String get agentPortalActivation =>
      _es ? 'Activacion del portal de agente' : 'Agent Portal Activation';
  String get agentActivationBody => _es
      ? 'Las cuentas de agentes de seguros se activan a traves del sitio web de VitaLink antes de habilitar el acceso a la app.\n\nTiene su codigo de activacion?'
      : 'Insurance agent accounts are activated through the VitaLink website before app access is enabled.\n\nDo you have your activation code?';
  String get iHaveMyActivationCode =>
      _es ? 'Tengo mi codigo de activacion' : 'I Have My Activation Code';
  String get iNeedActivationCode =>
      _es ? 'Necesito un codigo de activacion' : 'I Need An Activation Code';
  String get welcomeTo => _es ? 'Bienvenido a' : 'Welcome To';
  String get loginToYourAccount =>
      _es ? 'Iniciar sesion en su cuenta' : 'Log In to Your Account';
  String get registerForAccount =>
      _es ? 'Registrarse para una cuenta' : 'Register for an Account';

  String get userLogin => _es ? 'Inicio de usuario' : 'User Login';
  String get email => _es ? 'Correo electronico' : 'Email';
  String get password => _es ? 'Contrasena' : 'Password';
  String get enterEmail =>
      _es ? 'Ingrese su correo electronico' : 'Enter email';
  String get enterPassword => _es ? 'Ingrese su contrasena' : 'Enter password';
  String get enterAPassword =>
      _es ? 'Ingrese una contrasena' : 'Enter a password';
  String get passwordAtLeast10 => _es
      ? 'Debe tener al menos 10 caracteres'
      : 'Must be at least 10 characters';
  String get passwordNeedsUppercase => _es
      ? 'Debe contener al menos una letra mayuscula'
      : 'Must contain at least one uppercase letter';
  String get passwordNeedsSpecial => _es
      ? 'Debe contener al menos un caracter especial'
      : 'Must contain at least one special character';
  String get forgotPassword =>
      _es ? 'Olvido su contrasena?' : 'Forgot Password?';
  String get rememberMe => _es ? 'Recordarme' : 'Remember me';
  String get login => _es ? 'Iniciar sesion' : 'Login';
  String get loginFailed => _es ? 'Error al iniciar sesion' : 'Login failed';
  String get incorrectPassword =>
      _es ? 'Contrasena incorrecta' : 'Incorrect password';
  String get accountNotFound =>
      _es ? 'Cuenta no encontrada' : 'Account not found';
  String get newDeviceDetected =>
      _es ? 'Nuevo dispositivo detectado' : 'New Device Detected';
  String get deviceAlreadyActive => _es
      ? 'Esta cuenta ya esta activa en otro dispositivo.\n\nDesea cambiar a este dispositivo?'
      : 'This account is already active on another device.\n\nDo you want to switch to this device?';
  String get yes => _es ? 'SI' : 'YES';
  String get no => _es ? 'NO' : 'NO';

  String get userRegistration =>
      _es ? 'Registro de usuario' : 'User Registration';
  String get recoverActivationCode =>
      _es ? 'Recuperar codigo de activacion' : 'Recover Activation Code';
  String get recoverActivationCodeBody => _es
      ? 'Si compro VitaLink pero perdio su codigo de activacion, visite:\n\nmyvitalink.app/recover'
      : 'If you purchased VitaLink but lost your activation code, visit:\n\nmyvitalink.app/recover';
  String get close => _es ? 'Cerrar' : 'Close';
  String get enterActivationCode =>
      _es ? 'INGRESE SU CODIGO DE ACTIVACION' : 'ENTER YOUR ACTIVATION CODE';
  String get activationCode => _es ? 'Codigo de activacion' : 'Activation Code';
  String get activationCodeRequired =>
      _es ? 'Codigo de activacion requerido' : 'Activation code required';
  String get fullName => _es ? 'Nombre completo' : 'Full Name';
  String get nameRequired => _es ? 'Nombre requerido' : 'Name required';
  String get phone => _es ? 'Telefono' : 'Phone';
  String get addressLine1 => _es ? 'Direccion linea 1' : 'Address Line 1';
  String get addressRequired =>
      _es ? 'Direccion requerida' : 'Address required';
  String get city => _es ? 'Ciudad' : 'City';
  String get cityRequired => _es ? 'Ciudad requerida' : 'City required';
  String get state => _es ? 'Estado' : 'State';
  String get stateRequired => _es ? 'Estado requerido' : 'State required';
  String get zipCode => _es ? 'Codigo postal' : 'Zip Code';
  String get zipRequired => _es ? 'Codigo postal requerido' : 'Zip required';
  String get confirmPassword =>
      _es ? 'Confirmar contrasena' : 'Confirm Password';
  String get requiredField => _es ? 'Requerido' : 'Required';
  String get completeRegistration =>
      _es ? 'Completar registro' : 'Complete Registration';
  String get passwordsDontMatch =>
      _es ? 'Las contrasenas no coinciden' : 'Passwords don\u2019t match';
  String get passwordMinLength =>
      _es ? 'Minimo 10 caracteres' : '\u2265 10 characters';
  String get passwordUppercase =>
      _es ? 'Al menos 1 letra mayuscula' : 'At least 1 uppercase letter';
  String get passwordSpecial =>
      _es ? 'Al menos 1 caracter especial' : 'At least 1 special character';
  String get profileNotReady => _es
      ? 'Perfil no listo. Intentelo de nuevo.'
      : 'Profile not ready. Please try again.';
  String get failedToLoadQr =>
      _es ? 'No se pudo cargar el QR' : 'Failed to load QR';
  String get dateOfBirth => _es ? 'Fecha de nacimiento' : 'Date of Birth';
  String get dob => _es ? 'Fecha de nacimiento' : 'DOB';
  String get name => _es ? 'Nombre' : 'Name';
  String get emergencyContacts =>
      _es ? 'Contactos de emergencia' : 'Emergency Contacts';
  String emergencyContact(int number) {
    if (!_es) {
      return number == 1 ? 'Emergency Contact' : 'Emergency Contact $number';
    }
    return number == 1
        ? 'Contacto de emergencia'
        : 'Contacto de emergencia $number';
  }

  String get notAvailable => _es ? 'N/D' : 'N/A';
  String get allergies => _es ? 'Alergias' : 'Allergies';
  String get conditions => _es ? 'Condiciones' : 'Conditions';
  String get implantedDevices =>
      _es ? 'Dispositivos implantados' : 'Implanted Devices';
  String get implants => _es ? 'Implantes' : 'Implants';
  String get majorProcedures =>
      _es ? 'Procedimientos importantes' : 'Major Procedures';
  String get procedures => _es ? 'Procedimientos' : 'Procedures';
  String get bloodType => _es ? 'Tipo de sangre' : 'Blood Type';
  String get organDonor => _es ? 'Donante de organos' : 'Organ Donor';
  String get unknown => _es ? 'Desconocido' : 'Unknown';
  String get noPhone => _es ? 'Sin telefono' : 'No phone';
  String get showEmergencyQr =>
      _es ? 'Mostrar QR de emergencia' : 'Show Emergency QR';
  String get emergencyDisclaimer => _es
      ? 'VitaLink proporciona informacion de salud personal solo como referencia de emergencia. No reemplaza la atencion medica profesional. Siempre dependa de profesionales medicos.'
      : 'VitaLink provides personal health information for emergency reference only. It does not replace professional medical care. Always rely on medical professionals.';
  String get qrTokenMissing => _es
      ? 'Falta el token QR. Actualice el perfil.'
      : 'QR Token missing. Please refresh profile.';
  String emergencyInfoFor(String name) => name.isEmpty
      ? emergencyInfo
      : (_es ? '$emergencyInfo - $name' : 'Emergency Info - $name');
  String get emergencyQr => _es ? 'QR de emergencia' : 'Emergency QR';
  String get emergencyAccess =>
      _es ? 'Acceso de emergencia' : 'Emergency Access';
  String get emergencyQrInstructions => _es
      ? 'Escanee este codigo QR para ver la informacion de emergencia.\n\nSi la pagina muestra Sesion expirada, vuelva a escanear el QR.'
      : 'Scan this QR code to view emergency information.\n\nIf the page shows Session expired, rescan the QR.';
  String get hipaaSoaAuthorization =>
      _es ? 'Autorizacion HIPAA y SOA' : 'HIPAA & SOA Authorization';
  String get signAuthorization =>
      _es ? 'Firmar autorizacion' : 'Sign Authorization';
  String get clear => _es ? 'Borrar' : 'Clear';
  String get cancel => _es ? 'Cancelar' : 'Cancel';
  String get submit => _es ? 'Enviar' : 'Submit';
  String get noAgentLinked => _es
      ? 'No hay un agente vinculado a esta cuenta.'
      : 'No agent is linked to this account.';
  String get sentSuccessfully =>
      _es ? 'Enviado correctamente' : 'Sent Successfully';
  String get hipaaSentToAgent => _es
      ? 'Su autorizacion HIPAA y SOA se ha enviado a su agente.'
      : 'Your HIPAA & SOA authorization has been sent to your agent.';
  String get acknowledgeAgentDescription => _es
      ? 'Reconozco y autorizo a mi agente como se describe arriba.'
      : 'I acknowledge and authorize my agent as described above.';
  String get signSendMyInformation =>
      _es ? 'Firmar y enviar mi informacion' : 'Sign & Send My Information';
  String get userInfoShared => _es
      ? 'Informacion del usuario compartida (segun autorizacion)'
      : 'User Information Shared (Per Authorization)';
  String get physiciansProviders => _es
      ? 'Medicos / Proveedores de atencion medica'
      : 'Physicians / Healthcare Providers';
  String get noneListed => _es ? 'Ninguno listado.' : 'None listed.';
  String get recipientAgent =>
      _es ? 'Destinatario (Agente):' : 'Recipient (Agent):';
  String get signature => _es ? 'Firma: ' : 'Signature: ';
  String get date => _es ? 'Fecha' : 'Date';
  String get hipaaAuthorizationText => _es
      ? '''AUTORIZACIÓN HIPAA Y ALCANCE DE CITA DE MEDICARE

Al firmar abajo, autorizo a mi agente de seguros con licencia y/o agencia afiliada a acceder, recibir y usar SOLAMENTE la siguiente información con el propósito de ayudarme con educación e inscripción en planes de Medicare:

- Mis medicamentos listados
- Mis médicos / proveedores de atención médica listados

No se compartirán otros registros médicos, diagnósticos, notas de tratamiento, información financiera ni información personal no relacionada mediante esta autorización.

Entiendo:

- Esta autorización es voluntaria.
- Puedo negarme a firmar sin afectar mi elegibilidad, tratamiento o beneficios.
- Puedo revocar esta autorización en cualquier momento por escrito.
- La revocación no se aplicará a información ya divulgada.
- La información divulgada puede estar sujeta a nueva divulgación y puede dejar de estar protegida por regulaciones federales de privacidad.
- Esta autorización vence un (1) año desde la fecha de firma, a menos que sea revocada antes.

ALCANCE DE CITA DE MEDICARE (Requerido por CMS)

Acepto hablar sobre los siguientes tipos de productos de Medicare con mi agente con licencia:

- Medicare Advantage (Parte C)
- Planes de medicamentos recetados (Parte D)
- Suplemento de Medicare (Medigap)
- Dental / Visión / Audición
- Indemnización hospitalaria y productos relacionados

Entiendo:

- No estoy obligado a inscribirme en ningún plan.
- El agente solo puede hablar sobre los tipos de productos listados arriba.
- Firmar no me obliga a inscribirme.
- Este Alcance de Cita permanece válido por doce (12) meses, a menos que sea revocado.
'''
      : '''HIPAA AUTHORIZATION & MEDICARE SCOPE OF APPOINTMENT

By signing below, I authorize my licensed insurance agent and/or affiliated agency to access, receive, and use ONLY the following information for the purpose of assisting me with Medicare plan education and enrollment:

\u2022 My listed medications
\u2022 My listed physicians / healthcare providers

No other medical records, diagnoses, treatment notes, financial data, or unrelated personal information will be shared through this authorization.

I understand:

\u2022 This authorization is voluntary.
\u2022 I may refuse to sign without affecting my eligibility, treatment, or benefits.
\u2022 I may revoke this authorization at any time in writing.
\u2022 Revocation will not apply to information already disclosed.
\u2022 Information disclosed may be subject to redisclosure and may no longer be protected by federal privacy regulations.
\u2022 This authorization expires one (1) year from the date signed unless revoked earlier.

MEDICARE SCOPE OF APPOINTMENT (CMS Required)

I agree to discuss the following Medicare product types with my licensed agent:

\u2022 Medicare Advantage (Part C)
\u2022 Prescription Drug Plans (Part D)
\u2022 Medicare Supplement (Medigap)
\u2022 Dental / Vision / Hearing
\u2022 Hospital Indemnity and related products

I understand:

\u2022 I am not required to enroll in any plan.
\u2022 The agent may only discuss the product types listed above.
\u2022 Signing does not obligate me to enroll.
\u2022 This Scope of Appointment remains valid for twelve (12) months unless revoked.
''';
  String registrationFailed(String error) =>
      _es ? 'Registro fallido: $error' : 'Registration failed: $error';
  String get registrationFailedShort =>
      _es ? 'Registro fallido' : 'Registration failed';
  String get assistedOnboardingLoaded => _es
      ? 'Registro asistido por agente cargado. Revise esta informacion antes de completar el registro.'
      : 'Agent-assisted onboarding loaded. Please review this information before completing registration.';
  String get assistedOnboardingExpired => _es
      ? 'Esta sesion de registro ha vencido. Pida a su agente que inicie una nueva sesion con usted.'
      : 'This onboarding session has expired. Please ask your agent to start a new session with you.';
  String get reviewAgentEnteredDetails => _es
      ? 'Revise los detalles ingresados por el agente'
      : 'Review Agent-Entered Details';
  String emergencyContactNumber(int number) => _es
      ? 'Contacto de emergencia $number'
      : 'Emergency Contact $number';
  String get invalidActivationCode => _es
      ? 'Codigo de activacion invalido o inactivo'
      : 'Invalid or inactive activation code';
  String get emailRequired =>
      _es ? 'Correo electronico requerido' : 'Email required';
  String get enterValidEmail =>
      _es ? 'Ingrese un correo electronico valido' : 'Enter a valid email';
  String get checkEmailEnding => _es
      ? 'Revise el final del correo. Quiso decir .com?'
      : 'Check the email ending. Did you mean .com?';
  String get requestPasswordReset => _es
      ? 'Solicitar restablecimiento de contrasena'
      : 'Request Password Reset';
  String get resetPassword => _es ? 'Restablecer contrasena' : 'Reset Password';
  String get emailOrPhone =>
      _es ? 'Correo electronico o telefono' : 'Email or Phone';
  String get enterEmailOrPhone =>
      _es ? 'Ingrese correo electronico o telefono' : 'Enter email or phone';
  String get sendResetCode =>
      _es ? 'Enviar codigo de restablecimiento' : 'Send Reset Code';
  String get resetCodeSent =>
      _es ? 'Codigo de restablecimiento enviado' : 'Reset code sent';
  String get requestFailed => _es ? 'Solicitud fallida' : 'Request failed';
  String errorMessage(String error) => _es ? 'Error: $error' : 'Error: $error';
  String get enterEmailFirst => _es
      ? 'Ingrese primero su correo electronico'
      : 'Enter your email address first';
  String resetCodeSentTo(String target) => _es
      ? 'Codigo de restablecimiento enviado a $target'
      : 'Reset code sent to $target';
  String get failedToSendResetCode => _es
      ? 'No se pudo enviar el codigo de restablecimiento'
      : 'Failed to send reset code';
  String get success => _es ? 'Correcto' : 'Success';
  String get passwordResetSuccess => _es
      ? 'Su contrasena se ha restablecido correctamente.'
      : 'Your password has been reset successfully.';
  String get resetFailed => _es ? 'No se pudo restablecer' : 'Reset failed';
  String get resetStepOne => _es
      ? 'Paso 1: Le enviaremos por correo un codigo de restablecimiento de 6 digitos.'
      : "Step 1: We'll email you a 6-digit reset code.";
  String get emailAddress => _es ? 'Correo electronico' : 'Email Address';
  String get enterEmailAddress =>
      _es ? 'Ingrese su correo electronico' : 'Enter your email address';
  String get sixDigitResetCode =>
      _es ? 'Codigo de restablecimiento de 6 digitos' : '6-digit Reset Code';
  String get enterValidSixDigitCode => _es
      ? 'Ingrese un codigo valido de 6 digitos'
      : 'Enter valid 6-digit code';
  String get newPassword => _es ? 'Nueva contrasena' : 'New Password';
  String get passwordsDoNotMatch =>
      _es ? 'Las contrasenas no coinciden' : 'Passwords do not match';
}
