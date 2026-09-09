const DEFAULT_ANDROID_STORE_URL =
  "https://play.google.com/store/apps/details?id=com.etnaturals.vitalinkapp";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function parseInteger(value, fallback) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function readString(name, fallback) {
  const value = process.env[name];
  return value && value.trim() ? value.trim() : fallback;
}

function readReleaseNotes(name, fallback) {
  const raw = process.env[name];
  if (!raw || !raw.trim()) return fallback;

  try {
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) {
      return parsed.map(String).filter((item) => item.trim());
    }
  } catch (_) {
    // Comma-separated notes are easier to manage in Netlify env vars.
  }

  return raw
    .split("|")
    .map((item) => item.trim())
    .filter(Boolean);
}

function platformConfig(platform) {
  const normalized = platform === "ios" ? "IOS" : "ANDROID";
  const isAndroid = normalized === "ANDROID";

  return {
    latestBuild: parseInteger(
      process.env[`${normalized}_LATEST_BUILD`],
      isAndroid ? 110 : 0
    ),
    minRequiredBuild: parseInteger(process.env[`${normalized}_MIN_BUILD`], 0),
    latestVersion: readString(
      `${normalized}_LATEST_VERSION`,
      isAndroid ? "2.0.17" : ""
    ),
    title: readString(
      `${normalized}_UPDATE_TITLE`,
      "VitaLink Update Available"
    ),
    message: readString(
      `${normalized}_UPDATE_MESSAGE`,
      "A newer version of VitaLink is available. Please update for the latest fixes and improvements."
    ),
    storeUrl: readString(
      `${normalized}_STORE_URL`,
      isAndroid ? DEFAULT_ANDROID_STORE_URL : ""
    ),
    releaseNotes: readReleaseNotes(`${normalized}_RELEASE_NOTES`, [
      "Improved update reminders inside the app.",
      "Better Android login reliability.",
      "Image handling and stability improvements.",
    ]),
  };
}

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 204, headers };
  }

  if (event.httpMethod !== "POST") {
    return {
      statusCode: 405,
      headers,
      body: JSON.stringify({ success: false, error: "Method not allowed" }),
    };
  }

  try {
    const body = event.body ? JSON.parse(event.body) : {};
    const platform = String(body.platform || "android").toLowerCase();
    const currentBuild = parseInteger(body.currentBuild, 0);
    const currentVersion = String(body.currentVersion || "");
    const config = platformConfig(platform);

    const updateAvailable =
      currentBuild > 0 && config.latestBuild > currentBuild;
    const required =
      currentBuild > 0 && config.minRequiredBuild > currentBuild;

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: true,
        platform,
        currentBuild,
        currentVersion,
        latestBuild: config.latestBuild,
        latestVersion: config.latestVersion,
        minRequiredBuild: config.minRequiredBuild,
        updateAvailable,
        required,
        title: config.title,
        message: config.message,
        storeUrl: config.storeUrl,
        releaseNotes: config.releaseNotes,
      }),
    };
  } catch (error) {
    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: false,
        error: error.message || "Unable to check for updates",
      }),
    };
  }
};
