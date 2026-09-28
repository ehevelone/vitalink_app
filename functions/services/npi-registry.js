const NPPES_URL = "https://npiregistry.cms.hhs.gov/api/";

function normalizeText(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/\s+/g, " ");
}

function normalizePhone(value) {
  const withoutExtension = String(value || "").replace(
    /\s*(?:ext(?:ension)?\.?|x)\s*\d+\s*$/i,
    "",
  );
  const digits = withoutExtension.replace(/\D/g, "");
  return digits.length >= 10 ? digits.slice(-10) : digits;
}

function candidatesMatchingPhone(candidates, phone) {
  const target = normalizePhone(phone);
  if (target.length !== 10) return [];
  return (candidates || []).filter(
    (candidate) => normalizePhone(candidate.phone) === target,
  );
}

function splitProviderName(value) {
  const cleaned = String(value || "")
    .replace(/\b(dr|doctor|md|do|np|pa|aprn|fnp|pharmd)\.?\b/gi, " ")
    .replace(/\s+/g, " ")
    .trim();

  if (cleaned.includes(",")) {
    const [last, ...rest] = cleaned.split(",");
    const firstName = rest.join(" ").trim().split(/\s+/)[0];
    const commaLeft = last.trim();
    if (commaLeft.length === 1 && firstName.length > 1) {
      return { firstName: commaLeft, lastName: firstName };
    }
    if (firstName) return { firstName, lastName: commaLeft };
  }

  const parts = cleaned.replace(/,/g, " ").split(/\s+/).filter(Boolean);
  if (parts.length < 2) return { firstName: "", lastName: cleaned };
  return { firstName: parts[0], lastName: parts.at(-1) };
}

function providerCandidateMatchesName(candidate, searchedName) {
  const { firstName, lastName } = splitProviderName(searchedName);
  const candidateName = normalizeText(candidate?.displayName);
  const normalizedLast = normalizeText(lastName);
  const normalizedFirst = normalizeText(firstName).split(" ")[0] || "";
  if (!candidateName || !normalizedLast) return false;

  const lastMatches = candidateName === normalizedLast ||
    candidateName.endsWith(` ${normalizedLast}`);
  if (!lastMatches) return false;
  if (!normalizedFirst) return true;

  const candidateFirst = candidateName.split(" ")[0] || "";
  return candidateFirst.startsWith(normalizedFirst);
}

function firstLocationAddress(addresses) {
  return (
    (addresses || []).find((address) => address.address_purpose === "LOCATION") ||
    (addresses || [])[0] ||
    {}
  );
}

function primaryTaxonomy(taxonomies) {
  return (
    (taxonomies || []).find((taxonomy) => taxonomy.primary === true) ||
    (taxonomies || [])[0] ||
    {}
  );
}

function matchingTaxonomy(taxonomies, expectedTaxonomyCodes = []) {
  if (expectedTaxonomyCodes.length) {
    const expected = new Set(expectedTaxonomyCodes);
    const match = (taxonomies || []).find((taxonomy) =>
      expected.has(String(taxonomy.code || "")),
    );
    if (match) return match;
  }
  return primaryTaxonomy(taxonomies);
}

function mapNppesResult(result, expectedTaxonomyCodes = []) {
  const basic = result.basic || {};
  const address = firstLocationAddress(result.addresses);
  const taxonomy = matchingTaxonomy(
    result.taxonomies,
    expectedTaxonomyCodes,
  );
  const isOrganization = result.enumeration_type === "NPI-2";
  const personName = [basic.first_name, basic.middle_name, basic.last_name]
    .filter(Boolean)
    .join(" ");

  return {
    npi: String(result.number || ""),
    displayName: isOrganization ? basic.organization_name || "" : personName,
    credential: basic.credential || "",
    taxonomy: taxonomy.desc || "",
    taxonomyCode: taxonomy.code || "",
    address1: address.address_1 || "",
    address2: address.address_2 || "",
    city: address.city || "",
    state: address.state || "",
    postalCode: address.postal_code || "",
    phone: address.telephone_number || "",
    enumerationType: result.enumeration_type || "",
  };
}

function buildSearchParams({
  entityType,
  name,
  city,
  state,
  postalCode,
  taxonomyDescription,
}) {
  const params = new URLSearchParams({
    version: "2.1",
    limit: entityType === "pharmacy" ? "200" : "10",
  });
  params.set("enumeration_type", entityType === "pharmacy" ? "NPI-2" : "NPI-1");

  if (entityType === "pharmacy") {
    params.set("organization_name", name);
  } else {
    const { firstName, lastName } = splitProviderName(name);
    if (firstName.length === 1) params.set("limit", "200");
    // NPPES is inconsistent with one-letter first-name searches. Search the
    // last name and let the local candidate filter enforce the initial.
    if (firstName.length > 1) params.set("first_name", firstName);
    if (lastName) params.set("last_name", lastName);
  }

  if (city) params.set("city", city);
  if (state) params.set("state", state);
  if (postalCode) params.set("postal_code", postalCode);
  if (taxonomyDescription) {
    params.set("taxonomy_description", taxonomyDescription);
  }
  return params;
}

async function fetchNppes(
  params,
  fetchImpl = fetch,
  expectedTaxonomyCodes = [],
  excludedTaxonomyCodes = [],
) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8000);
  try {
    const response = await fetchImpl(`${NPPES_URL}?${params}`, {
      headers: { Accept: "application/json" },
      signal: controller.signal,
    });
    if (!response.ok) {
      throw new Error(`NPPES returned ${response.status}`);
    }
    const payload = await response.json();
    const expected = new Set(expectedTaxonomyCodes);
    const excluded = new Set(excludedTaxonomyCodes);
    return (payload.results || [])
      .filter((result) => result?.basic?.status !== "D")
      .filter(
        (result) =>
          !(result.taxonomies || []).some((taxonomy) =>
            excluded.has(String(taxonomy.code || "")),
          ),
      )
      .filter(
        (result) =>
          !expected.size ||
          (result.taxonomies || []).some((taxonomy) =>
            expected.has(String(taxonomy.code || "")),
          ),
      )
      .map((result) => mapNppesResult(result, expectedTaxonomyCodes))
      .filter((candidate) => /^\d{10}$/.test(candidate.npi));
  } finally {
    clearTimeout(timeout);
  }
}

async function searchNpi(input, fetchImpl = fetch) {
  const candidates = await fetchNppes(
    buildSearchParams(input),
    fetchImpl,
    input.taxonomyCodes || [],
    input.excludedTaxonomyCodes || [],
  );
  return input.entityType === "provider"
    ? candidates.filter((candidate) =>
        providerCandidateMatchesName(candidate, input.name))
    : candidates;
}

async function getNpiByNumber(npi, fetchImpl = fetch) {
  if (!/^\d{10}$/.test(String(npi || ""))) return null;
  const results = await fetchNppes(
    new URLSearchParams({ version: "2.1", number: String(npi) }),
    fetchImpl,
  );
  return results.find((candidate) => candidate.npi === String(npi)) || null;
}

module.exports = {
  buildSearchParams,
  candidatesMatchingPhone,
  getNpiByNumber,
  mapNppesResult,
  normalizePhone,
  normalizeText,
  providerCandidateMatchesName,
  searchNpi,
  splitProviderName,
};
