// Push notification text in each phone's language.
//
// The app sends its display language when it registers a device (body
// `language`, plus an Accept-Language header on every request). It is stored
// in user_devices.app_language / agent_devices.app_language. Phones from
// older app versions have no stored language and get English.

function normalizeLanguage(value) {
  const text = String(value || "").trim().toLowerCase();
  if (!text) return null;
  return text.startsWith("es") ? "es" : "en";
}

function headerValue(event, name) {
  const headers = event?.headers || {};
  const key = Object.keys(headers).find((k) => k.toLowerCase() === name);
  return key ? headers[key] : null;
}

// Language this request came from, or null when the app did not say.
function requestLanguage(event, body) {
  return normalizeLanguage(
    body?.language || body?.app_language || headerValue(event, "accept-language")
  );
}

function deviceLanguage(row) {
  return normalizeLanguage(row?.app_language) || "en";
}

const TEXT = {
  messageFrom: {
    en: ({ name }) => `Message from ${name || "Your Agent"}`,
    es: ({ name }) => `Mensaje de ${name || "su agente"}`,
  },
  campaignPrep: {
    en: () => "Medicare enrollment is approaching. Please tap here to securely send your information before your upcoming appointment.",
    es: () => "Se acerca la inscripción de Medicare. Toque aquí para enviar su información de forma segura antes de su próxima cita.",
  },
  campaignAep: {
    en: () => "It's time for your Medicare Enrollment Review! Please tap here to securely send your updated information to your agent.",
    es: () => "¡Es hora de su revisión de inscripción de Medicare! Toque aquí para enviar su información actualizada a su agente de forma segura.",
  },
  campaignOep: {
    en: () => "There’s still time to review your Medicare coverage. Tap here to securely send your updated information to your agent.",
    es: () => "Todavía hay tiempo para revisar su cobertura de Medicare. Toque aquí para enviar su información actualizada a su agente de forma segura.",
  },
  campaignGeneral: {
    en: () => "Tap here to securely send your Medicare information so your agent can keep your coverage up to date.",
    es: () => "Toque aquí para enviar su información de Medicare de forma segura y que su agente pueda mantener su cobertura al día.",
  },
  appUpdatedTitle: {
    en: () => "VitaLink Updated",
    es: () => "VitaLink se actualizó",
  },
  appUpdatedBody: {
    en: () => "VitaLink has been updated with improvements and new features. Open the app to see what's new.",
    es: () => "VitaLink se actualizó con mejoras y funciones nuevas. Abra la aplicación para ver las novedades.",
  },
  updateAvailableTitle: {
    en: () => "VitaLink update available",
    es: () => "Hay una actualización de VitaLink disponible",
  },
  updateAvailableBody: {
    en: () => "A new version of VitaLink is ready. Tap to update for the latest fixes and features.",
    es: () => "Hay una versión nueva de VitaLink. Toque para actualizar y obtener las correcciones y funciones más recientes.",
  },
  profileUpdateTitle: {
    en: () => "Profile update available",
    es: () => "Hay una actualización de perfil disponible",
  },
  profileUpdateBody: {
    en: ({ profile }) => `${profile || "A VitaLink profile"} has an update ready to apply.`,
    es: ({ profile }) => `${profile || "Un perfil de VitaLink"} tiene una actualización lista para aplicar.`,
  },
  caregiverConnectedTitle: {
    en: () => "Caregiver connected",
    es: () => "Cuidador conectado",
  },
  caregiverConnectedBody: {
    en: ({ profile }) => `Open VitaLink to send ${profile || "the shared profile"}.`,
    es: ({ profile }) => `Abra VitaLink para enviar ${profile || "el perfil compartido"}.`,
  },
  sharingEndedTitle: {
    en: () => "Profile sharing ended",
    es: () => "Se dejó de compartir el perfil",
  },
  sharingEndedBody: {
    en: () => "A shared VitaLink profile is no longer receiving updates.",
    es: () => "Un perfil compartido de VitaLink ya no recibe actualizaciones.",
  },
  sharedRemovedTitle: {
    en: () => "Shared profile removed",
    es: () => "Perfil compartido eliminado",
  },
  sharedRemovedBody: {
    en: ({ profile }) => `The caregiver removed ${profile || "the shared profile"} from their device.`,
    es: ({ profile }) => `El cuidador eliminó ${profile || "el perfil compartido"} de su dispositivo.`,
  },
  deviceMovedTitle: {
    en: () => "VitaLink moved to a new device",
    es: () => "VitaLink se trasladó a un dispositivo nuevo",
  },
  deviceMovedBody: {
    en: () => "This old device has been disabled. Its local VitaLink profiles were not erased.",
    es: () => "Este dispositivo anterior se desactivó. Sus perfiles locales de VitaLink no se borraron.",
  },
  deviceDisabledTitle: {
    en: () => "VitaLink device disabled",
    es: () => "Dispositivo de VitaLink desactivado",
  },
  deviceDisabledBody: {
    en: () => "This lost or stolen device has been disabled and its local VitaLink profiles will be erased.",
    es: () => "Este dispositivo perdido o robado se desactivó y sus perfiles locales de VitaLink se borrarán.",
  },
  prospectRequestTitle: {
    en: () => "Prospect Contact Request",
    es: () => "Solicitud de contacto de un posible cliente",
  },
  prospectRequestBody: {
    en: ({ channels, topic }) => `A prospect requested ${channels} contact about ${topic}.`,
    es: ({ channels, topic }) => `Un posible cliente pidió contacto por ${channels} sobre ${topic}.`,
  },
  newReferralTitle: {
    en: () => "New VitaLink Referral",
    es: () => "Nuevo referido de VitaLink",
  },
  newReferralBody: {
    en: ({ name, preference }) => `${name} preferred contact: ${preference}.`,
    es: ({ name, preference }) => `${name} prefiere que lo contacten por: ${preference}.`,
  },
};

const CHANNELS_ES = {
  call: "llamada",
  text: "mensaje de texto",
  email: "correo electrónico",
  phone: "teléfono",
};

const TOPICS_ES = {
  medicare: "Medicare",
  "life insurance": "seguro de vida",
  insurance: "seguros",
};

function notificationText(key, language, vars = {}) {
  const entry = TEXT[key];
  if (!entry) throw new Error(`Unknown notification text: ${key}`);
  return (entry[language] || entry.en)(vars);
}

function channelLabel(channel, language) {
  if (language !== "es") return channel;
  return CHANNELS_ES[String(channel).toLowerCase()] || channel;
}

function topicLabel(topic, language) {
  if (language !== "es") return topic;
  return TOPICS_ES[String(topic || "").trim().toLowerCase()] || topic;
}

// Like messaging.sendEachForMulticast, but each language group gets its own
// text. `targets` items need { token, language }. `build(language, tokens)`
// returns the multicast message. The combined response keeps
// `responses[i]` aligned with `targets[i]`.
async function sendLocalizedMulticast(messaging, targets, build) {
  const groups = new Map();
  targets.forEach((target, index) => {
    const language = target.language || "en";
    if (!groups.has(language)) groups.set(language, []);
    groups.get(language).push(index);
  });

  const responses = new Array(targets.length);
  let successCount = 0;
  let failureCount = 0;
  for (const [language, indexes] of groups) {
    const tokens = indexes.map((i) => targets[i].token);
    const response = await messaging.sendEachForMulticast(build(language, tokens));
    successCount += response?.successCount || 0;
    failureCount += response?.failureCount || 0;
    (response?.responses || []).forEach((result, j) => {
      responses[indexes[j]] = result;
    });
  }
  return { successCount, failureCount, responses };
}

module.exports = {
  channelLabel,
  deviceLanguage,
  normalizeLanguage,
  notificationText,
  requestLanguage,
  sendLocalizedMulticast,
  topicLabel,
};

// Adds the language columns. Senders call this before selecting app_language.
const db = require("./db");
const { schemaOnce } = require("./schema-once");

const ensureLanguageColumns = schemaOnce("notification-language:columns", async () => {
  await db.query(`ALTER TABLE user_devices ADD COLUMN IF NOT EXISTS app_language TEXT`);
  await db.query(`ALTER TABLE IF EXISTS agent_devices ADD COLUMN IF NOT EXISTS app_language TEXT`);
});

module.exports.ensureLanguageColumns = ensureLanguageColumns;
