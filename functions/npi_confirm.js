const { getNpiByNumber } = require("./services/npi-registry");
const {
  authenticate,
  cacheConfirmedCandidate,
} = require("./services/npi-verification");

function reply(statusCode, body) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    },
    body: JSON.stringify(body),
  };
}

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") return reply(200, {});
  if (event.httpMethod !== "POST") return reply(405, { success: false, error: "Method Not Allowed" });

  try {
    const body = JSON.parse(event.body || "{}");
    const identity = await authenticate(body);
    if (!identity) return reply(403, { success: false, error: "Unauthorized" });

    const entityType = String(body.entityType || "").toLowerCase();
    const searchedName = String(body.searchedName || "").trim();
    const npi = String(body.candidate?.npi || "").trim();
    if (!["provider", "pharmacy"].includes(entityType) || searchedName.length < 2 || !/^\d{10}$/.test(npi)) {
      return reply(400, { success: false, error: "Invalid confirmation" });
    }

    // Never trust candidate details supplied by the app; re-read the NPI from CMS.
    const candidate = await getNpiByNumber(npi);
    if (!candidate) return reply(404, { success: false, error: "NPI was not found" });

    await cacheConfirmedCandidate({
      entityType,
      searchedName,
      candidate,
      actor: identity.actor,
    });

    return reply(200, {
      success: true,
      verificationStatus: "verified",
      verifiedBy: identity.actor,
      candidate,
    });
  } catch (error) {
    console.error("npi_confirm error:", error);
    return reply(502, { success: false, error: "Provider confirmation is temporarily unavailable" });
  }
};
