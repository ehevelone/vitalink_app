// Spanish versions of the messages the server sends back to the app.
//
// The server answers in English. ApiService passes `error` and `message`
// through [localizeServerMessage] so a Spanish user sees Spanish text.
// Status codes the app checks (DEVICE_ACTIVE, TRANSFER_REQUIRED,
// Unauthorized, ...) are deliberately left out so those checks keep working.

String localizeServerMessage(String text, String languageCode) {
  if (languageCode != 'es') return text;
  final trimmed = text.trim();
  final exact = _serverMessagesEs[trimmed];
  if (exact != null) return exact;

  final serverReturned = RegExp(r'^Server returned (\d+)$').firstMatch(trimmed);
  if (serverReturned != null) {
    return 'El servidor respondió con el código ${serverReturned.group(1)}';
  }
  if (trimmed.startsWith('Server error: ')) {
    return 'Error del servidor: ${trimmed.substring('Server error: '.length)}';
  }
  final cms = RegExp(
    r'^No current-year CMS benefits found for (.+)\. The CMS import may not have loaded this plan yet\.$',
  ).firstMatch(trimmed);
  if (cms != null) {
    return 'No se encontraron beneficios de CMS del año actual para ${cms.group(1)}. Es posible que la importación de CMS aún no haya cargado este plan.';
  }
  return text;
}

const Map<String, String> _serverMessagesEs = {
  'A valid entity type and name are required':
      'Se requiere un tipo de entidad y un nombre válidos',
  'A valid pharmacy name is required':
      'Se requiere un nombre de farmacia válido',
  'Account does not match the active session':
      'La cuenta no coincide con la sesión activa',
  'Account not found': 'No se encontró la cuenta',
  'Account not found.': 'No se encontró la cuenta.',
  'Agent attestation is required': 'Se requiere la declaración del agente',
  'Agent inactive': 'Agente inactivo',
  'Agent not found': 'No se encontró al agente',
  'Agent profile updated ✅': 'Perfil del agente actualizado ✅',
  'Agent registration complete': 'Registro del agente completado',
  'Benefits shown for the current Medicare plan year only.':
      'Se muestran los beneficios solo del año actual del plan de Medicare.',
  'Calendly link must start with http:// or https://':
      'El enlace de Calendly debe comenzar con http:// o https://',
  'Choose an approved message.': 'Elija un mensaje aprobado.',
  'Choose how you would like to be contacted.':
      'Elija cómo prefiere que lo contacten.',
  'Connected agent not found.': 'No se encontró el agente conectado.',
  'Create a transfer code on the old device before replacing it.':
      'Cree un código de traslado en el dispositivo anterior antes de reemplazarlo.',
  'Device is not active': 'El dispositivo no está activo',
  'Email is required': 'El correo electrónico es obligatorio',
  'Email required': 'El correo electrónico es obligatorio',
  'Email sent successfully': 'Correo enviado correctamente',
  'Email server error': 'Error del servidor de correo',
  'Email, password, and device are required':
      'Se requieren el correo electrónico, la contraseña y el dispositivo',
  'Enter a phone number or email for the referral.':
      'Ingrese un número de teléfono o correo electrónico para el referido.',
  'Enter a transfer code': 'Ingrese un código de traslado',
  'Enter an access code': 'Ingrese un código de acceso',
  'Enter both the email and phone number for the person you want to share with.':
      'Ingrese el correo electrónico y el número de teléfono de la persona con quien desea compartir.',
  'If a matching account was found, an email has been sent.':
      'Si se encontró una cuenta que coincide, se envió un correo electrónico.',
  'Invalid JSON body': 'Solicitud no válida',
  'Invalid JSON': 'Solicitud no válida',
  'Invalid agent code': 'Código de agente no válido',
  'Invalid base64': 'Datos no válidos',
  'Invalid confirmation': 'Confirmación no válida',
  'Invalid item type': 'Tipo de elemento no válido',
  'Invalid password': 'Contraseña no válida',
  'Invalid payload': 'Datos no válidos',
  'Invalid referral status.': 'Estado de referido no válido.',
  'Invalid relationship.': 'Parentesco no válido.',
  'Invalid request body': 'Solicitud no válida',
  'Invalid reset code': 'Código de restablecimiento no válido',
  'Invalid role': 'Función no válida',
  'Invalid step': 'Paso no válido',
  'Invalid transfer chunk': 'Parte del traslado no válida',
  'Invalid transfer package': 'Paquete de traslado no válido',
  'Item not found': 'No se encontró el elemento',
  'Messaging is available only to confirmed clients.':
      'Los mensajes solo están disponibles para clientes confirmados.',
  'Method Not Allowed': 'Método no permitido',
  'Method not allowed': 'Método no permitido',
  'Missing agent code': 'Falta el código de agente',
  'Missing agent or client': 'Falta el agente o el cliente',
  'Missing agent or item': 'Falta el agente o el elemento',
  'Missing agentEmail': 'Falta el correo electrónico del agente',
  'Missing agentId or token': 'Falta el ID del agente o el token',
  'Missing agentId': 'Falta el ID del agente',
  'Missing credentials': 'Faltan las credenciales',
  'Missing device': 'Falta el dispositivo',
  'Missing email': 'Falta el correo electrónico',
  'Missing encrypted profile packages':
      'Faltan los paquetes de perfil cifrados',
  'Missing invite code': 'Falta el código de invitación',
  'Missing onboarding code or user session':
      'Falta el código de incorporación o la sesión del usuario',
  'Missing onboarding code': 'Falta el código de incorporación',
  'Missing or invalid id / profiles':
      'Falta el ID o los perfiles, o no son válidos',
  'Missing package id': 'Falta el ID del paquete',
  'Missing parameters': 'Faltan parámetros',
  'Missing referral id.': 'Falta el ID del referido.',
  'Missing required fields': 'Faltan campos obligatorios',
  'Missing share id': 'Falta el ID de lo compartido',
  'Missing transfer': 'Falta el traslado',
  'Missing user, device ID, or notification token':
      'Falta el usuario, el ID del dispositivo o el token de notificaciones',
  'NPI was not found': 'No se encontró el NPI',
  'No Medicare plan ID found on this card.':
      'No se encontró un ID de plan de Medicare en esta tarjeta.',
  'No account found': 'No se encontró ninguna cuenta',
  'No agent found': 'No se encontró ningún agente',
  'No business card image provided':
      'No se proporcionó una imagen de la tarjeta de presentación',
  'No connected agent found for this VitaLink account.':
      'No se encontró un agente conectado a esta cuenta de VitaLink.',
  'No eligible devices': 'No hay dispositivos elegibles',
  'No fields provided to update': 'No se proporcionaron campos para actualizar',
  'No image provided': 'No se proporcionó ninguna imagen',
  'No reset code found': 'No se encontró ningún código de restablecimiento',
  'No unlock code found for agent':
      'No se encontró un código de desbloqueo para el agente',
  'Password update failed': 'No se pudo actualizar la contraseña',
  'Policy verification did not match the connected agent.':
      'La verificación de la póliza no coincide con el agente conectado.',
  'Prospect messages are currently paused.':
      'Los mensajes a posibles clientes están en pausa.',
  'Prospect messaging is available only to confirmed prospects.':
      'Los mensajes a posibles clientes solo están disponibles para posibles clientes confirmados.',
  'Provider confirmation is temporarily unavailable':
      'La confirmación del proveedor no está disponible por el momento',
  'Provider registry lookup is temporarily unavailable':
      'La búsqueda en el registro de proveedores no está disponible por el momento',
  'Referral name is required.': 'El nombre del referido es obligatorio.',
  'Referral not found.': 'No se encontró el referido.',
  'Reset code expired': 'El código de restablecimiento venció',
  'Revocation push timed out':
      'La notificación de desactivación tardó demasiado',
  'Server error while fetching promo code ❌':
      'Error del servidor al obtener el código promocional ❌',
  'Server error while scanning business card':
      'Error del servidor al escanear la tarjeta de presentación',
  'Server error while sending notifications':
      'Error del servidor al enviar las notificaciones',
  'Server error while updating agent ❌':
      'Error del servidor al actualizar el agente ❌',
  'Server error while updating user ❌':
      'Error del servidor al actualizar el usuario ❌',
  'Server error': 'Error del servidor',
  'Share invite not found': 'No se encontró la invitación para compartir',
  'Share link not found': 'No se encontró el enlace para compartir',
  'Shared profile not found': 'No se encontró el perfil compartido',
  'Text is required': 'El texto es obligatorio',
  'That access code has already been used': 'Ese código de acceso ya se usó',
  'That access code is not valid': 'Ese código de acceso no es válido',
  'That email address is already in use':
      'Ese correo electrónico ya está en uso',
  "That transfer code doesn't match. Check the code on your old phone and try again.":
      'Ese código de traslado no coincide. Revise el código en su teléfono anterior e intente de nuevo.',
  'That transfer code is invalid, expired, or is still being prepared':
      'Ese código de traslado no es válido, venció o todavía se está preparando',
  'The client/user must accept the agreement.':
      'El cliente o usuario debe aceptar el acuerdo.',
  'The client/user must make this choice.':
      'El cliente o usuario debe tomar esta decisión.',
  'The signed HIPAA and Scope of Appointment PDF is required':
      'Se requiere el PDF firmado de HIPAA y Alcance de la Cita.',
  'The medication list was too long to read in one photo.':
      'La lista de medicamentos era demasiado larga para leerla en una sola foto.',
  'The user must make this choice.': 'El usuario debe tomar esta decisión.',
  'This message is no longer available.': 'Este mensaje ya no está disponible.',
  'This onboarding session has expired and cannot be reopened.':
      'Esta sesión de incorporación venció y no se puede volver a abrir.',
  'This onboarding session has expired. Please ask your agent to start a new session with you.':
      'Esta sesión de incorporación venció. Pídale a su agente que inicie una nueva sesión con usted.',
  'Too many incorrect codes. Try again in 15 minutes.':
      'Demasiados códigos incorrectos. Intente de nuevo en 15 minutos.',
  'Transfer chunk not found': 'No se encontró la parte del traslado',
  'Transfer not found': 'No se encontró el traslado',
  'Unable to send prospect message.':
      'No se pudo enviar el mensaje a posibles clientes.',
  'Unable to send your request.': 'No se pudo enviar su solicitud.',
  'Unauthorized client': 'Cliente no autorizado',
  'Unknown action': 'Acción desconocida',
  'Unknown message.': 'Mensaje desconocido.',
  'Unsupported message category.': 'Categoría de mensaje no compatible.',
  'Unsupported prospect category': 'Categoría de posible cliente no compatible',
  'Update package not found': 'No se encontró el paquete de actualización',
  'User not found': 'No se encontró al usuario',
  'User profile updated ✅': 'Perfil de usuario actualizado ✅',
  'User registered successfully ✅': 'Usuario registrado correctamente ✅',
  'Request timed out': 'La solicitud tardó demasiado',
};
