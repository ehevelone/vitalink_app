const {
  candidatesMatchingPhone,
  normalizePhone,
  normalizeText,
  searchNpi,
} = require("./services/npi-registry");
const { taxonomiesForSpecialty } = require("./services/npi-taxonomies");
const {
  candidatesWithinRadius,
  nearbyZipPrefixes,
  normalizeZip,
} = require("./services/zip-radius");
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

function isVaPharmacyName(value) {
  const name = normalizeText(value);
  if (
    ["va", "vamc", "veterans affairs", "veterans administration"].includes(
      name,
    )
  ) {
    return true;
  }
  return (
    /\bva\b/.test(name) ||
    /\bvamc\b/.test(name) ||
    /\bveterans?\b/.test(name)
  ) && /\b(pharmacy|pharm)\b/.test(name);
}

// Store-name searches such as "Wal-Mart*" also return vision centers and other
// non-pharmacy locations, so local searches keep only pharmacy taxonomies.
// Mail order (3336M0002X) is left out here and searched separately.
const LOCAL_PHARMACY_TAXONOMY_CODES = [
  "333600000X",
  "3336C0002X",
  "3336C0003X",
  "3336C0004X",
  "3336H0001X",
  "3336I0012X",
  "3336L0003X",
  "3336M0003X",
  "3336N0007X",
  "3336S0011X",
];

// Words that pharmacy labels add but NPPES registrations often lack, e.g.
// "MEIJER PHARMACY #237" is registered as "MEIJER STORES LIMITED PARTNERSHIP".
const STORE_NAME_NOISE = /\b(pharmacy|pharmacies|pharm|rx|drug|drugs|drugstore|store|stores|inc|llc|co|corp|corporation|company|the|of)\b/g;

// Looser "starts with" spellings of the label name, tried only when the exact
// name finds nothing: "Winn-Dixie*", "Winn Dixie*", "WinnDixie*", "Fry's*".
function looseStoreNameVariants(name) {
  const withoutNumbers = String(name || "").replace(/#\s*\d+/g, " ");
  const words = normalizeText(withoutNumbers)
    .replace(/\b\d+\b/g, " ")
    .replace(STORE_NAME_NOISE, " ")
    .trim()
    .split(/\s+/)
    .filter(Boolean);
  if (!words.length || words.join("").length < 3) return [];
  const apostropheWords = String(withoutNumbers)
    .toLowerCase()
    .replace(/[^a-z0-9' ]+/g, " ")
    .replace(STORE_NAME_NOISE, " ")
    .trim()
    .split(/\s+/)
    .filter(Boolean);
  return [
    `${words.join(" ")}*`,
    `${words.join("-")}*`,
    `${words.join("")}*`,
    `${apostropheWords.join(" ")}*`,
  ].filter((value, index, values) =>
    value.replace(/[^a-z0-9]/g, "").length >= 3 && values.indexOf(value) === index);
}

async function searchPharmacy({ name, city, state, postalCode, phone, exactZip = false }) {
  const zip = String(postalCode || "").match(/^\d{5}/)?.[0] || "";
  // exactZip: the ZIP came from the pharmacy's own address on the bottle, so
  // search only that ZIP. Otherwise it is the client's home ZIP and gets a
  // 15-mile radius.
  const onlyThisZip = exactZip && Boolean(zip);
  const vaPharmacy = isVaPharmacyName(name);
  const nameVariants = [name];
  const normalizedName = normalizeText(name);
  // Walmart pharmacies are registered as "WALMART INC."; "WAL-MART STORES"
  // entries are usually vision centers, which the taxonomy filter drops.
  if (normalizedName.includes("walmart")) nameVariants.push("Walmart*", "Wal-Mart*");
  if (normalizedName.includes("walgreens")) nameVariants.push("Walgreen*");
  if (normalizedName.includes("cvs")) nameVariants.push("CVS*");
  // NPPES matches punctuation literally, so "HyVee" never finds "HY-VEE".
  const compactName = normalizedName.replace(/[^a-z0-9]/g, "");
  if (compactName.includes("hyvee")) nameVariants.push("Hy-Vee*", "Hy Vee*");
  // Sam's Club pharmacies are registered as "SAMS WEST INC".
  if (compactName.includes("samsclub") || compactName.startsWith("sams")) {
    nameVariants.push("Sams*", "Sam's*");
  }

  // 1. Auto-detect: with the bottle's ZIP and phone, find the pharmacy in that
  // ZIP whose registered phone matches, whatever name it is registered under.
  // Only the matching store is ever returned.
  if (onlyThisZip && !vaPharmacy && normalizePhone(phone).length === 10) {
    const inZip = uniqueCandidates(await searchNpi({
      entityType: "pharmacy",
      name: "",
      postalCode: zip,
      taxonomyDescription: "Pharmacy",
      taxonomyCodes: LOCAL_PHARMACY_TAXONOMY_CODES,
      excludedTaxonomyCodes: ["3336M0002X"],
    }));
    const matchingPhone = candidatesMatchingPhone(inZip, phone);
    if (matchingPhone.length) return { candidates: matchingPhone, phoneMatched: true };
  }

  // 2. The label name (plus known chain spellings).
  const first = await searchPharmacyByName({
    name, nameVariants, city, state, zip, phone, onlyThisZip, vaPharmacy,
  });
  if (first.candidates.length || vaPharmacy) return first;

  // 3. Loosen the name: drop "Pharmacy", store numbers, and punctuation.
  const looseVariants = looseStoreNameVariants(name)
    .filter((variant) => !nameVariants.includes(variant));
  if (looseVariants.length) {
    const loose = await searchPharmacyByName({
      name, nameVariants: looseVariants, city, state, zip, phone, onlyThisZip, vaPharmacy,
    });
    if (loose.candidates.length) return loose;
  }

  // 4. Nothing in the bottle's ZIP: look nearby so the client can choose.
  if (onlyThisZip) {
    return searchPharmacyByName({
      name,
      nameVariants: [...nameVariants, ...looseVariants],
      city,
      state,
      zip,
      phone,
      onlyThisZip: false,
      vaPharmacy,
    });
  }
  return first;
}

async function searchPharmacyByName({
  name, nameVariants, city, state, zip, phone, onlyThisZip, vaPharmacy,
}) {
  if (zip && !onlyThisZip && !vaPharmacy) {
    const prefixes = nearbyZipPrefixes(zip, 15);
    const nearbySets = await Promise.all(prefixes.flatMap((prefix) =>
      nameVariants.map((searchName) => searchNpi({
        entityType: "pharmacy",
        name: searchName,
        postalCode: `${prefix}*`,
        taxonomyCodes: LOCAL_PHARMACY_TAXONOMY_CODES,
        excludedTaxonomyCodes: ["3336M0002X"],
      })),
    ));
    const withinRadius = candidatesWithinRadius(
      uniqueCandidates(nearbySets.flat()),
      zip,
      15,
    );
    const matchingPhone = candidatesMatchingPhone(withinRadius, phone);
    if (matchingPhone.length) {
      return { candidates: matchingPhone, phoneMatched: true };
    }
    if (withinRadius.length) {
      return { candidates: withinRadius, phoneMatched: false };
    }
  }

  const scopes = [];
  if (zip) scopes.push(state ? { postalCode: zip, state } : { postalCode: zip });
  if (!onlyThisZip) {
    if (city && state) scopes.push({ city, state });
    if (state) scopes.push({ state });
    if (city && !state) scopes.push({ city });
    if (phone) scopes.push({});
  }

  let nearby = [];
  for (const scope of scopes) {
    const searches = vaPharmacy ? [""] : nameVariants;
    const results = uniqueCandidates((await Promise.all(searches.map(
      (searchName) => searchNpi({
        entityType: "pharmacy",
        name: searchName,
        ...scope,
        ...(vaPharmacy
          ? {
              taxonomyDescription: "Department of Veterans Affairs (VA) Pharmacy",
              taxonomyCodes: ["332100000X"],
            }
          : {
              taxonomyCodes: LOCAL_PHARMACY_TAXONOMY_CODES,
              excludedTaxonomyCodes: ["3336M0002X"],
            }),
      }),
    ))).flat())
      .filter((candidate) => matchesLocation(candidate, scope));
    const matchingPhone = candidatesMatchingPhone(results, phone);
    if (matchingPhone.length) return { candidates: matchingPhone, phoneMatched: true };
    if (!nearby.length && Object.keys(scope).length) nearby = results;
    if (!phone && results.length) break;
  }
  return { candidates: nearby, phoneMatched: false };
}

async function searchRegistryScope({ entityType, name, city, state, postalCode, specialty }) {
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
  const narrowed = uniqueCandidates(resultSets.flat());
  const allNameMatches = await searchNpi(base);
  return uniqueCandidates([...narrowed, ...allNameMatches]);
}

async function searchRegistry(options) {
  let exact = await searchRegistryScope(options);
  if (!exact.length && String(options.name || "").includes(",")) {
    const [left, right] = String(options.name).split(",").map((part) => part.trim());
    if (left && right) {
      exact = await searchRegistryScope({ ...options, name: `${right}, ${left}` });
    }
  }
  const originZip = normalizeZip(options.postalCode);
  if (!originZip) return exact;

  const exactLocation = exact.filter(
    (candidate) => normalizeZip(candidate.postalCode) === originZip,
  );
  if (exactLocation.length) return exactLocation;

  const prefixes = nearbyZipPrefixes(originZip, 15);
  if (!prefixes.length) return exact;
  const nearbySets = await Promise.all(prefixes.map((prefix) =>
    searchRegistryScope({
      ...options,
      city: "",
      state: "",
      postalCode: `${prefix}*`,
    }),
  ));
  return candidatesWithinRadius(
    uniqueCandidates(nearbySets.flat()),
    originZip,
    15,
  );
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
    const exactZip = entityType === "pharmacy" && body.exactZip === true;
    const vaPharmacy = entityType === "pharmacy" && isVaPharmacyName(name);
    const includeVa = entityType === "provider" && body.includeVa === true;
    if (!["provider", "pharmacy"].includes(entityType) || name.length < 2) {
      return reply(400, { success: false, error: "A valid entity type and name are required" });
    }
    if (mailOrder && name.replace(/[?*]/g, "").trim().length < 2) {
      return reply(400, { success: false, error: "A valid pharmacy name is required" });
    }

    const cachedResults = body.specialty || mailOrder || includeVa || vaPharmacy || (entityType === "pharmacy" && !phone && !city && !state && !postalCode)
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
      ? vaPharmacy
        ? await searchPharmacy({ name, city, state, postalCode, phone, exactZip })
        : mailOrder
        ? {
            candidates: uniqueCandidates(await searchNpi({
              entityType: "pharmacy",
              name: `${name.replace(/[?*]/g, "").trim()}*`,
              taxonomyDescription: "Mail Order Pharmacy",
              taxonomyCodes: ["3336M0002X"],
            })),
            phoneMatched: false,
          }
        : await searchPharmacy({ name, city, state, postalCode, phone, exactZip })
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

exports._test = { searchPharmacy, searchRegistry };
