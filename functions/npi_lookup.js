const { searchNpi } = require("./services/npi-registry");
const {
  authenticate,
  cacheConfirmedCandidate,
  findCachedCandidates,
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

function uniqueCandidates(candidates) {
  const seen = new Set();
  return candidates.filter((candidate) => {
    if (!candidate?.npi || seen.has(candidate.npi)) return false;
    seen.add(candidate.npi);
    return true;
  });
}

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") return reply(200, {});
  if (event.httpMethod !== "POST") return reply(405, { success: false, error: "Method Not Allowed" });

  try {
    const body = JSON.parse(event.body || "{}");
    const identity = await authenticate(body);
    if (!identity) return reply(403, { success: false, error: "Unauthorized" });

    const entityType = String(body.entityType || "").toLowerCase();
    const name = String(body.name || "").trim();
    if (!["provider", "pharmacy"].includes(entityType) || name.length < 2) {
      return reply(400, { success: false, error: "A valid entity type and name are required" });
    }

    const cached = await findCachedCandidates({
      entityType,
      name,
      city: body.city,
      state: body.state,
    });
    if (cached.length) {
      return reply(200, {
        success: true,
        verificationStatus: "needs_review",
        npi: null,
        candidates: cached,
      });
    }

    const registryCandidates = await searchNpi({
      entityType,
      name,
      city: String(body.city || "").trim(),
      state: String(body.state || "").trim().toUpperCase(),
      postalCode: String(body.postalCode || "").trim(),
    });

    if (registryCandidates.length === 1) {
      const candidate = registryCandidates[0];
      await cacheConfirmedCandidate({
        entityType,
        searchedName: name,
        candidate,
        actor: "auto",
      });
      return reply(200, {
        success: true,
        verificationStatus: "verified",
        npi: candidate.npi,
        verifiedBy: "auto",
        candidates: [candidate],
      });
    }

    const candidates = uniqueCandidates(registryCandidates).slice(0, 4);

    return reply(200, {
      success: true,
      verificationStatus: candidates.length ? "needs_review" : "unverified",
      npi: null,
      candidates,
    });
  } catch (error) {
    console.error("npi_lookup error:", error);
    return reply(502, { success: false, error: "Provider registry lookup is temporarily unavailable" });
  }
};
