const {
  normalizeText,
  providerCandidateMatchesName,
  splitProviderName,
} = require("./npi-registry");

const VA_DIRECTORY_URL =
  "https://www.accesstocare.va.gov/OurProviders/SearchResults";

const STATE_KEYS = Object.freeze({
  AL: 1, AK: 2, AZ: 3, AR: 4, CA: 5, CO: 6, CT: 7, DE: 8, DC: 9,
  FL: 10, GA: 11, HI: 12, ID: 13, IL: 14, IN: 15, IA: 16, KS: 17,
  KY: 18, LA: 19, ME: 20, MD: 21, MA: 22, MI: 23, MN: 24, MS: 25,
  MO: 26, MT: 27, NE: 28, NV: 29, NH: 30, NJ: 31, NM: 32, NY: 33,
  NC: 34, ND: 35, OH: 36, OK: 37, OR: 38, PA: 39, PR: 40, RI: 41,
  SC: 42, SD: 43, TN: 44, TX: 45, UT: 46, VT: 47, VA: 48, WA: 49,
  WV: 50, WI: 51, WY: 52,
});

function extractSearchResults(html) {
  const startMarker = '"searchResults":';
  const endMarker = ',"selectedState"';
  const start = html.indexOf(startMarker);
  if (start < 0) return [];
  const valueStart = start + startMarker.length;
  const end = html.indexOf(endMarker, valueStart);
  if (end < 0) return [];
  try {
    const parsed = JSON.parse(html.slice(valueStart, end));
    return Array.isArray(parsed) ? parsed : [];
  } catch (_) {
    return [];
  }
}

function mapVaProvider(provider, directoryUpdated) {
  const displayName = [provider.firstName, provider.lastName]
    .filter(Boolean)
    .join(" ")
    .trim();
  return {
    npi: null,
    displayName,
    credential: provider.occupation || "",
    taxonomy: provider.occupation || "",
    address1: provider.facilityAddress || "",
    address2: "",
    city: provider.city || "",
    state: provider.state || "",
    postalCode: String(provider.zipCode || "").trim(),
    phone: "",
    enumerationType: "",
    registry: "va",
    isVaProvider: true,
    vaFacility: provider.vaFacility || "",
    vaServiceLine: String(provider.serviceProductLine || "").trim(),
    vaDirectoryUpdated: directoryUpdated || "",
  };
}

async function searchVaProviders({ name, state }, fetchImpl = fetch) {
  const stateKey = STATE_KEYS[String(state || "").trim().toUpperCase()];
  const { lastName } = splitProviderName(name);
  if (!stateKey || !lastName) return [];

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8000);
  try {
    const params = new URLSearchParams({
      s: String(stateKey),
      n: lastName,
    });
    const response = await fetchImpl(`${VA_DIRECTORY_URL}?${params}`, {
      headers: {
        Accept: "text/html",
        "User-Agent": "VitaLink provider verification",
      },
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(`VA directory returned ${response.status}`);
    const html = await response.text();
    const updatedMatch = html.match(/"lastUpdated":"([^"]+)"/);
    return extractSearchResults(html)
      .map((provider) => mapVaProvider(provider, updatedMatch?.[1]))
      .filter((candidate) => providerCandidateMatchesName(candidate, name));
  } finally {
    clearTimeout(timeout);
  }
}

function mergeProviderCandidates(npiCandidates, vaCandidates) {
  const merged = npiCandidates.map((candidate) => ({ ...candidate }));
  for (const vaCandidate of vaCandidates) {
    const matchingNpi = merged.find(
      (candidate) =>
        normalizeText(candidate.displayName) ===
          normalizeText(vaCandidate.displayName) ||
        providerCandidateMatchesName(candidate, vaCandidate.displayName),
    );
    if (matchingNpi) {
      Object.assign(matchingNpi, {
        registry: "nppes_va",
        isVaProvider: true,
        vaFacility: vaCandidate.vaFacility,
        vaServiceLine: vaCandidate.vaServiceLine,
        vaDirectoryUpdated: vaCandidate.vaDirectoryUpdated,
      });
    } else {
      merged.push(vaCandidate);
    }
  }
  return merged;
}

module.exports = {
  extractSearchResults,
  mapVaProvider,
  mergeProviderCandidates,
  searchVaProviders,
};
