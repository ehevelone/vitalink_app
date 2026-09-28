const {
  candidatesMatchingPhone,
  normalizePhone,
  normalizeText,
  searchNpi,
} = require("./services/npi-registry");
const { taxonomiesForSpecialty } = require("./services/npi-taxonomies");
const {
  mergeProviderCandidates,
  searchVaProviders,
} = require("./services/va-provider-registry");
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
    const key = candidate?.npi
      ? `npi:${candidate.npi}`
      : candidate?.isVaProvider
        ? `va:${normalizeText(candidate.displayName)}:${normalizeText(candidate.vaFacility)}`
        : "";
    if (!key || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

const STATE_CODES = {
  alabama: "AL", alaska: "AK", arizona: "AZ", arkansas: "AR", california: "CA",
  colorado: "CO", connecticut: "CT", delaware: "DE", "district of columbia": "DC",
  florida: "FL", georgia: "GA", hawaii: "HI", idaho: "ID", illinois: "IL",
  indiana: "IN", iowa: "IA", kansas: "KS", kentucky: "KY", louisiana: "LA",
  maine: "ME", maryland: "MD", massachusetts: "MA", michigan: "MI",
  minnesota: "MN", mississippi: "MS", missouri: "MO", montana: "MT",
  nebraska: "NE", nevada: "NV", "new hampshire": "NH", "new jersey": "NJ",
  "new mexico": "NM", "new york": "NY", "north carolina": "NC",
  "north dakota": "ND", ohio: "OH", oklahoma: "OK", oregon: "OR",
  pennsylvania: "PA", "rhode island": "RI", "south carolina": "SC",
  "south dakota": "SD", tennessee: "TN", texas: "TX", utah: "UT",
  vermont: "VT", virginia: "VA", washington: "WA", "west virginia": "WV",
  wisconsin: "WI", wyoming: "WY",
};

function normalizeState(value) {
  const text = String(value || "").trim();
  const code = text.toUpperCase();
  if (Object.values(STATE_CODES).includes(code)) return code;
  return STATE_CODES[text.toLowerCase()] || "";
}

function matchesLocation(candidate, scope) {
  if (scope.state && String(candidate.state || "").toUpperCase() !== scope.state) return false;
  if (scope.city && normalizeText(candidate.city) !== normalizeText(scope.city)) return false;
  const zip = String(scope.postalCode || "").match(/^\d{5}/)?.[0];
  if (zip && String(candidate.postalCode || "").slice(0, 5) !== zip) return false;
  return true;
}

async function searchPharmacy({ name, city, state, postalCode, phone }) {
  const zip = String(postalCode || "").match(/^\d{5}/)?.[0] || "";
  const scopes = [];
  if (zip) scopes.push(state ? { postalCode: zip, state } : { postalCode: zip });
  if (city && state) scopes.push({ city, state });
  if (state) scopes.push({ state });
  if (city && !state) scopes.push({ city });
  if (phone) scopes.push({});

  let nearby = [];
  for (const scope of scopes) {
    const results = uniqueCandidates(await searchNpi({
      entityType: "pharmacy", name, ...scope,
      excludedTaxonomyCodes: ["3336M0002X"],
    }))
      .filter((candidate) => matchesLocation(candidate, scope));
    const matchingPhone = candidatesMatchingPhone(results, phone);
    if (matchingPhone.length) return { candidates: matchingPhone, phoneMatched: true };
    if (!nearby.length && Object.keys(scope).length) nearby = results;
    if (!phone && results.length) break;
  }
  return { candidates: nearby, phoneMatched: false };
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
    const city = String(body.city || "").trim();
    const state = normalizeState(body.state);
    const postalCode = String(body.postalCode || "").trim();
    const mailOrder = entityType === "pharmacy" && body.mailOrder === true;
    const includeVa = entityType === "provider" && body.includeVa === true;
    if (!["provider", "pharmacy"].includes(entityType) || name.length < 2) {
      return reply(400, { success: false, error: "A valid entity type and name are required" });
    }
    if (mailOrder && name.replace(/[?*]/g, "").trim().length < 2) {
      return reply(400, { success: false, error: "A valid pharmacy name is required" });
    }

    const cachedResults = body.specialty || mailOrder || includeVa || (entityType === "pharmacy" && !phone && !city && !state && !postalCode)
      ? []
      : await findCachedCandidates({
          entityType,
          name,
          city: entityType === "pharmacy" && phone ? "" : city,
          state: entityType === "pharmacy" && phone ? "" : state,
          postalCode: entityType === "pharmacy" && phone ? "" : postalCode,
          phone: entityType === "pharmacy" ? phone : "",
        });
    const cached = entityType === "pharmacy" && !phone
      ? cachedResults.filter((candidate) => matchesLocation(candidate, { city, state, postalCode }))
      : cachedResults;
    const eligibleCached = entityType === "pharmacy"
      ? cached.filter((candidate) => !/mail order pharmacy/i.test(candidate.taxonomy || ""))
      : cached;
    if (eligibleCached.length) {
      if (entityType === "pharmacy" && phone && eligibleCached.length === 1) {
        return reply(200, {
          success: true,
          verificationStatus: "verified",
          npi: eligibleCached[0].npi,
          verifiedBy: "auto",
          candidates: eligibleCached,
        });
      }
      return reply(200, {
        success: true,
        verificationStatus: "needs_review",
        npi: null,
        candidates: eligibleCached,
      });
    }

    const pharmacyResult = entityType === "pharmacy"
      ? mailOrder
        ? {
            candidates: uniqueCandidates(await searchNpi({
              entityType: "pharmacy",
              name: `${name.replace(/[?*]/g, "").trim()}*`,
              taxonomyDescription: "Mail Order Pharmacy",
              taxonomyCodes: ["3336M0002X"],
            })),
            phoneMatched: false,
          }
        : await searchPharmacy({ name, city, state, postalCode, phone })
      : null;
    let registryCandidates;
    if (pharmacyResult) {
      registryCandidates = pharmacyResult.candidates;
    } else {
      const [npiCandidates, vaCandidates] = await Promise.all([
        searchRegistry({
          entityType, name, city, state, postalCode,
          specialty: String(body.specialty || "").trim(),
        }),
        includeVa
          ? searchVaProviders({ name, state }).catch((error) => {
              console.warn("VA provider directory lookup failed:", error.message);
              return [];
            })
          : Promise.resolve([]),
      ]);
      registryCandidates = mergeProviderCandidates(npiCandidates, vaCandidates);
    }

    const canAutoVerify = entityType === "pharmacy"
      ? pharmacyResult.phoneMatched && registryCandidates.length === 1
      : false;

    if (canAutoVerify) {
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

    const candidates = uniqueCandidates(registryCandidates).slice(
      0, entityType === "pharmacy" ? 10 : 4,
    );

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
