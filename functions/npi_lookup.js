const {
  candidatesMatchingPhone,
  normalizePhone,
  searchNpi,
} = require("./services/npi-registry");
const { taxonomiesForSpecialty } = require("./services/npi-taxonomies");
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

async function searchRegistry({ entityType, name, city, state, postalCode, specialty }) {
  const base = { entityType, name, city, state, postalCode };
  if (entityType !== "provider" || !specialty) {
    return searchNpi(base);
  }

  const taxonomies = taxonomiesForSpecialty(specialty);
  if (!taxonomies.length) return searchNpi(base);

  const taxonomyGroups = new Map();
  for (const taxonomy of taxonomies) {
    const codes = taxonomyGroups.get(taxonomy.description) || [];
    codes.push(taxonomy.code);
    taxonomyGroups.set(taxonomy.description, codes);
  }
  const resultSets = await Promise.all(
    [...taxonomyGroups.entries()].map(([taxonomyDescription, taxonomyCodes]) =>
      searchNpi({ ...base, taxonomyDescription, taxonomyCodes }),
    ),
  );
  return uniqueCandidates(resultSets.flat());
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
    const phone = normalizePhone(body.phone);
    if (!["provider", "pharmacy"].includes(entityType) || name.length < 2) {
      return reply(400, { success: false, error: "A valid entity type and name are required" });
    }

    const cached = body.specialty
      ? []
      : await findCachedCandidates({
          entityType,
          name,
          city: entityType === "pharmacy" && phone ? "" : body.city,
          state: entityType === "pharmacy" && phone ? "" : body.state,
          phone: entityType === "pharmacy" ? phone : "",
        });
    if (cached.length) {
      if (entityType === "pharmacy" && phone && cached.length === 1) {
        return reply(200, {
          success: true,
          verificationStatus: "verified",
          npi: cached[0].npi,
          verifiedBy: "auto",
          candidates: cached,
        });
      }
      return reply(200, {
        success: true,
        verificationStatus: "needs_review",
        npi: null,
        candidates: cached,
      });
    }

    const registryCandidates = await searchRegistry({
      entityType,
      name,
      city:
        entityType === "pharmacy" ? "" : String(body.city || "").trim(),
      state:
        entityType === "pharmacy"
          ? ""
          : String(body.state || "").trim().toUpperCase(),
      postalCode:
        entityType === "pharmacy"
          ? ""
          : String(body.postalCode || "").trim(),
      specialty: String(body.specialty || "").trim(),
    });

    const phoneMatches = candidatesMatchingPhone(registryCandidates, phone);
    const confidentCandidates =
      entityType === "pharmacy" && phone ? phoneMatches : registryCandidates;

    if (confidentCandidates.length === 1) {
      const candidate = confidentCandidates[0];
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

    const reviewPool = phoneMatches.length ? phoneMatches : registryCandidates;
    const candidates = uniqueCandidates(reviewPool).slice(0, 4);

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
