const { verifyUserSession } = require("./services/user-auth");

const RXNAV_BASE = "https://rxnav.nlm.nih.gov/REST";
const PRODUCT_TYPES = new Set(["SCD", "SBD", "GPCK", "BPCK"]);
const BRAND_TYPES = new Set(["SBD", "BPCK"]);
const REQUEST_TIMEOUT_MS = 6000;

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

function clean(value) {
  return String(value || "").trim();
}

function normalized(value) {
  return clean(value)
    .toLowerCase()
    .replace(/[\u00b5\u03bc]/g, "mc")
    .replace(/\s+/g, " ");
}

function flattenProducts(payload) {
  const groups = payload?.drugGroup?.conceptGroup;
  if (!Array.isArray(groups)) return [];
  return groups.flatMap((group) => {
    if (!PRODUCT_TYPES.has(group?.tty)) return [];
    return (Array.isArray(group.conceptProperties) ? group.conceptProperties : [])
      .filter((product) => product?.suppress !== "Y")
      .map((product) => ({ ...product, tty: product.tty || group.tty }));
  });
}

function brandName(product) {
  return clean(product?.name).match(/\[([^\]]+)\]\s*$/)?.[1] || "";
}

function stripLeadingReleasePrefix(value) {
  return clean(value).replace(
    /^(?:(?:modified|osmotic)\s+)?\d+\s*hr\s+/i,
    "",
  );
}

function stripLeadingPackagePrefix(value) {
  let result = stripLeadingReleasePrefix(value);
  const doseList = /^(?:\d+(?:\.\d+)?\s*(?:MCG|MG|G|ML|MEQ|UNT|UNIT|UNITS)(?:\s*,\s*|\s+))+(?:dose\s+)?/i;
  const packageQuantity = /^\d+(?:\.\d+)?\s*(?:ML|MG|G|UNT|UNIT|UNITS)\s+/i;
  const applicationNumber = /^(?:NDA|ANDA|BLA)\s*-?\s*\d+\s+/i;
  const actuationCount = /^\d+\s*ACTUAT\s+/i;
  for (let index = 0; index < 5; index += 1) {
    const next = stripLeadingReleasePrefix(result)
      .replace(applicationNumber, "")
      .replace(actuationCount, "")
      .replace(doseList, "")
      .replace(packageQuantity, "");
    if (next === result) break;
    result = next;
  }
  return result;
}

function withoutApplicationNumber(value) {
  return clean(value).replace(/^(?:NDA|ANDA|BLA)\s*-?\s*\d+\s+/i, "");
}

function baseIngredientWithoutSalt(value) {
  const salts = "acetate|besylate|calcium|fumarate|hydrochloride|potassium|sodium|succinate|sulfate|tartrate";
  return clean(value).replace(new RegExp(`\\s+(?:${salts})$`, "i"), "");
}

function ingredientNames(product, { stripPackagePrefixes = false } = {}) {
  const withoutBrand = clean(product?.name).replace(/\s*\[[^\]]+\]\s*$/, "");
  const name = (stripPackagePrefixes ? stripLeadingPackagePrefix : stripLeadingReleasePrefix)(
    withoutBrand,
  );
  return name.split(" / ").map((part) => normalized(
    part.replace(/\b\d+(?:\.\d+)?\s*(?:MCG|MG|G|MEQ|UNT|UNIT|UNITS|%)\b.*$/i, ""),
  )).filter(Boolean);
}

function requestedIngredients(name) {
  return normalized(name)
    .replace(/\b(?:er|xr|xl|sr|sa|cr|dr|ec|odt)\b/g, " ")
    .replace(/\b(?:extended|sustained|controlled|delayed)\s+release\b/g, " ")
    .replace(/\b(?:enteric coated|disintegrating|chewable|effervescent|sublingual|modified|osmotic)\b/g, " ")
    .replace(/\b(?:12|24)\s*hr\b/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .split(/\s*(?:\/|\+|\band\b)\s*/)
    .filter(Boolean);
}

function ingredientMatches(requested, actual) {
  return actual === requested || actual.startsWith(`${requested} `);
}

function productsMatchingName(requestedName, products, options = {}) {
  const requested = normalized(requestedName);
  if (!requested) return [];
  const brandMatches = products.filter((product) =>
    BRAND_TYPES.has(product.tty) && normalized(brandName(product)) === requested,
  );
  if (brandMatches.length) return brandMatches;

  const wantedIngredients = requestedIngredients(requestedName);
  const wantsCombination = wantedIngredients.length > 1;
  return products.filter((product) => {
    if (BRAND_TYPES.has(product.tty)) return false;
    const actualIngredients = ingredientNames(product, options);
    if (!wantsCombination && actualIngredients.length !== 1) return false;
    if (actualIngredients.length !== wantedIngredients.length) return false;
    return wantedIngredients.every((wanted) =>
      actualIngredients.some((actual) => ingredientMatches(wanted, actual)),
    );
  });
}

function strengthValues(value) {
  const values = [];
  const pattern = /\b(\d+(?:\.\d+)?)\s*(MCG|MG|G)\b/gi;
  for (const match of clean(value).matchAll(pattern)) {
    const amount = Number(match[1]);
    const unit = match[2].toUpperCase();
    const micrograms = unit === "G"
      ? amount * 1000000
      : unit === "MG"
        ? amount * 1000
        : amount;
    values.push(micrograms);
  }
  return values;
}

function doseMatchesProduct(dose, product) {
  const requested = strengthValues(dose);
  if (!requested.length) return false;
  // "250 mg" on a label is per tablet/capsule; it must not match a liquid
  // concentration such as "250 MG/ML" unless the label itself says per mL.
  if (!/\/\s*ML\b/i.test(clean(dose)) && /\/\s*ML\b/i.test(clean(product?.name))) {
    return false;
  }
  const actual = strengthValues(product?.name);
  return requested.every((value) => actual.some((candidate) =>
    Math.abs(candidate - value) < 0.000001,
  ));
}

function formMatchesProduct(form, product) {
  const requested = normalized(form);
  if (!requested) return true;
  const haystack = normalized(`${product?.name || ""} ${product?.synonym || ""}`);
  const aliases = {
    tab: "tablet",
    tabs: "tablet",
    cap: "capsule",
    caps: "capsule",
  };
  const wanted = aliases[requested] || requested;
  return haystack.includes(wanted);
}

function dosageModifiers(value) {
  const text = normalized(value);
  const modifiers = new Set();
  if (/\b(?:er|xr|xl|sr|sa|cr|extended release|sustained release|controlled release)\b/.test(text) ||
      /\b(?:12|24)\s*hr\b/.test(text)) {
    modifiers.add("extended");
  }
  if (/\b(?:dr|ec|delayed release|enteric coated)\b/.test(text)) {
    modifiers.add("delayed");
  }
  if (/\b(?:odt|disintegrating)\b/.test(text)) modifiers.add("disintegrating");
  if (/\bchewable\b/.test(text)) modifiers.add("chewable");
  if (/\beffervescent\b/.test(text)) modifiers.add("effervescent");
  if (/\bsublingual\b/.test(text)) modifiers.add("sublingual");
  if (/\bmodified\b/.test(text)) modifiers.add("modified");
  if (/\bosmotic\b/.test(text)) modifiers.add("osmotic");
  return modifiers;
}

function filterByModifiers(products, requestedName, requestedForm) {
  const wanted = dosageModifiers(`${requestedName} ${requestedForm}`);
  if (wanted.size) {
    return products.filter((product) => {
      const actual = dosageModifiers(product.name);
      return [...wanted].every((modifier) => actual.has(modifier));
    });
  }
  const unmodified = products.filter((product) => dosageModifiers(product.name).size === 0);
  return unmodified.length ? unmodified : products;
}

function modifierSortKey(value) {
  const modifiers = [...dosageModifiers(value)].sort();
  return modifiers.length ? `1:${modifiers.join(",")}` : "0:";
}

function outpatientFormRank(value) {
  const text = normalized(value);
  if (/\b(?:oral )?(?:tablet|capsule)\b/.test(text)) return 0;
  if (/\b(?:inhaler|metered dose inhal|inhalation aerosol|inhalation powder)\b/.test(text)) return 0;
  if (/\b(?:pen injector|autoinjector)\b/.test(text)) return 0;
  if (/\b(?:ophthalmic|otic|nasal)\b/.test(text) && /\b(?:drop|solution|spray)\b/.test(text)) return 0;
  if (/\bpatch\b/.test(text)) return 1;
  if (/\b(?:cream|ointment|topical|gel)\b/.test(text)) return 2;
  if (/\b(?:oral solution|oral suspension|syrup|elixir)\b/.test(text)) return 3;
  if (/\b(?:inject|prefilled syringe|vial)\b/.test(text)) return 9;
  return 4;
}

function uniqueProducts(products) {
  const seen = new Set();
  return products.filter((product) => {
    const key = clean(product?.rxcui);
    if (!key || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function productParts(product, representativeNdc = "", ndcSource = "") {
  const displayName = withoutApplicationNumber(product?.name);
  const withoutBrand = displayName.replace(/\s*\[[^\]]+\]\s*$/, "");
  const formMatch = withoutBrand.match(/\b(Oral|Topical|Sublingual|Buccal|Nasal|Ophthalmic|Otic|Rectal|Vaginal)?\s*(Tablet|Capsule|Solution|Suspension|Injection|Cream|Ointment|Patch|Spray|Powder|Film|Lozenge|Suppository|Gel)\b.*$/i);
  const form = clean(formMatch?.[0]);
  const beforeForm = formMatch ? withoutBrand.slice(0, formMatch.index).trim() : withoutBrand;
  const strengthMatch = beforeForm.match(/(?:\d+(?:\.\d+)?\s*(?:MCG|MG|G|ML|UNIT|UNITS|%)(?:\s*\/\s*\d+(?:\.\d+)?\s*(?:MCG|MG|G|ML))?(?:\s*\/\s*(?:ACTUAT|DOSE|HR))?)(?:\s*\/\s*[^/]+)?$/i);
  return {
    rxcui: clean(product?.rxcui),
    displayName,
    strength: clean(strengthMatch?.[0]),
    form,
    drugType: BRAND_TYPES.has(product?.tty) ? "brand" : "generic",
    tty: clean(product?.tty),
    ndc: clean(representativeNdc),
    ndcSource: clean(ndcSource),
  };
}

function activeRxcuiFromStatus(status) {
  if (clean(status?.status).toUpperCase() === "ACTIVE" &&
      clean(status?.conceptStatus).toLowerCase() === "active") {
    return clean(status.rxcui);
  }
  if (clean(status?.status).toUpperCase() !== "OBSOLETE") return "";
  const history = Array.isArray(status.ndcHistory)
    ? status.ndcHistory
    : Array.isArray(status.ndcHistory?.ndcTime)
      ? status.ndcHistory.ndcTime
      : [];
  return clean([...history].reverse().find((entry) => clean(entry?.activeRxcui))?.activeRxcui);
}

function createRxNavClient(fetchImpl = global.fetch) {
  let displayNamesPromise;

  async function get(path, params = {}) {
    const url = new URL(`${RXNAV_BASE}${path}`);
    for (const [key, value] of Object.entries(params)) {
      if (clean(value)) url.searchParams.set(key, clean(value));
    }
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
    try {
      const response = await fetchImpl(url, { signal: controller.signal });
      if (!response.ok) throw new Error(`RxNav returned HTTP ${response.status}`);
      return await response.json();
    } finally {
      clearTimeout(timeout);
    }
  }

  async function productForRxcui(rxcui) {
    const payload = await get(`/rxcui/${encodeURIComponent(rxcui)}/properties.json`);
    const properties = payload?.properties;
    if (!properties || !PRODUCT_TYPES.has(properties.tty)) return null;
    return properties;
  }

  async function representativeNdc(rxcui) {
    const payload = await get(`/rxcui/${encodeURIComponent(rxcui)}/ndcs.json`);
    const ndcs = payload?.ndcGroup?.ndcList?.ndc;
    return Array.isArray(ndcs) ? clean(ndcs[0]) : "";
  }

  async function displayNames() {
    displayNamesPromise ||= get("/displaynames.json").then((payload) => {
      const terms = payload?.displayTermsList?.term;
      return Array.isArray(terms) ? terms.map(clean).filter(Boolean) : [];
    }).catch((error) => {
      displayNamesPromise = undefined;
      throw error;
    });
    return displayNamesPromise;
  }

  async function verify({ name, dose, form, ndc }) {
    const labelNdc = clean(ndc);
    if (labelNdc) {
      const payload = await get("/ndcstatus.json", { ndc: labelNdc, history: "1" });
      const status = payload?.ndcStatus || {};
      const rxcui = activeRxcuiFromStatus(status);
      if (!rxcui || !clean(name)) return { status: "no_match" };
      const product = await productForRxcui(rxcui);
      if (!product || productsMatchingName(name, [product]).length !== 1) {
        return { status: "no_match" };
      }
      return {
        status: "sure",
        match: productParts(product, clean(status.ndc11) || labelNdc, "label"),
      };
    }

    if (!clean(name) || !clean(dose)) return { status: "no_match" };
    let payload = await get("/drugs.json", { name: clean(name) });
    let products = flattenProducts(payload);
    if (!products.length && dosageModifiers(name).size) {
      const baseName = requestedIngredients(name).join(" / ");
      if (baseName && normalized(baseName) !== normalized(name)) {
        payload = await get("/drugs.json", { name: baseName });
        products = flattenProducts(payload);
      }
    }
    let matches = productsMatchingName(name, products)
      .filter((candidate) =>
        doseMatchesProduct(dose, candidate) && formMatchesProduct(form, candidate),
      );
    matches = uniqueProducts(filterByModifiers(matches, name, form));
    if (matches.length !== 1) return { status: "no_match" };
    const product = matches[0];
    const ndcValue = await representativeNdc(product.rxcui);
    return {
      status: "sure",
      match: productParts(product, ndcValue, ndcValue ? "representative" : ""),
    };
  }

  async function search(text) {
    const query = clean(text);
    if (query.length < 2) return [];
    const queryNormalized = normalized(query);
    const names = await displayNames();
    const prefix = names.filter((name) => normalized(name).startsWith(queryNormalized));
    const contains = names.filter((name) =>
      !normalized(name).startsWith(queryNormalized) &&
      normalized(name).includes(queryNormalized),
    );
    const byLengthThenName = (a, b) => a.length - b.length || a.localeCompare(b);
    const direct = [
      ...prefix.sort(byLengthThenName),
      ...contains.sort(byLengthThenName),
    ]
      .slice(0, 10)
      .map((name) => ({ name }));
    if (direct.length) return direct;

    const payload = await get("/approximateTerm.json", {
      term: query,
      maxEntries: "20",
      option: "1",
    });
    const candidates = payload?.approximateGroup?.candidate;
    if (!Array.isArray(candidates)) return [];
    const seen = new Set();
    return candidates
      .filter((candidate) => clean(candidate?.source).toUpperCase() === "RXNORM")
      .map((candidate) => ({ rxcui: clean(candidate.rxcui), name: clean(candidate.name) }))
      .filter((candidate) => {
        const key = normalized(candidate.name);
        if (!candidate.rxcui || !key || seen.has(key)) return false;
        seen.add(key);
        return true;
      })
      .slice(0, 10);
  }

  async function strengths(drug) {
    const query = clean(drug);
    if (query.length < 2) return [];
    const synonyms = {
      "vitamin d": "ergocalciferol",
      "vitamin d2": "ergocalciferol",
      "vitamin d3": "cholecalciferol",
      "vitamin b12": "cyanocobalamin",
      "fish oil": "omega-3-acid ethyl esters",
    };
    let lookupName = query;
    let payload = await get("/drugs.json", { name: lookupName });
    let products = uniqueProducts(productsMatchingName(
      lookupName,
      flattenProducts(payload),
      { stripPackagePrefixes: true },
    ));
    const synonym = synonyms[normalized(query)];
    if (!products.length && synonym) {
      lookupName = synonym;
      payload = await get("/drugs.json", { name: lookupName });
      products = uniqueProducts(productsMatchingName(
        lookupName,
        flattenProducts(payload),
        { stripPackagePrefixes: true },
      ));
    }
    const baseIngredient = baseIngredientWithoutSalt(query);
    if (!products.length && baseIngredient !== query) {
      lookupName = baseIngredient;
      payload = await get("/drugs.json", { name: lookupName });
      products = uniqueProducts(productsMatchingName(
        lookupName,
        flattenProducts(payload),
        { stripPackagePrefixes: true },
      ));
    }
    // "Guanfacine ER" is not an RxNorm name: look up "guanfacine", then keep
    // only the extended-release products the label asked for.
    const wantedModifiers = dosageModifiers(query);
    if (!products.length && wantedModifiers.size) {
      const baseName = requestedIngredients(query).join(" / ");
      if (baseName && normalized(baseName) !== normalized(query)) {
        lookupName = baseName;
        payload = await get("/drugs.json", { name: lookupName });
        const baseProducts = uniqueProducts(productsMatchingName(
          lookupName,
          flattenProducts(payload),
          { stripPackagePrefixes: true },
        ));
        const withModifiers = baseProducts.filter((product) => {
          const actual = dosageModifiers(product.name);
          return [...wantedModifiers].every((modifier) => actual.has(modifier));
        });
        products = withModifiers.length ? withModifiers : baseProducts;
      }
    }
    return products
      .map((product) => {
        const option = productParts(product);
        if (synonym === "ergocalciferol" &&
            /\bergocalciferol\b/i.test(option.displayName) &&
            strengthValues(option.strength)[0] === 1250) {
          option.displayName += " (50,000 units)";
        }
        return option;
      })
      .sort((a, b) => {
        const formOrder = outpatientFormRank(a.displayName) - outpatientFormRank(b.displayName);
        if (formOrder) return formOrder;
        const modifierOrder = modifierSortKey(a.displayName)
          .localeCompare(modifierSortKey(b.displayName));
        if (modifierOrder) return modifierOrder;
        const firstA = strengthValues(a.displayName)[0] ?? Number.MAX_SAFE_INTEGER;
        const firstB = strengthValues(b.displayName)[0] ?? Number.MAX_SAFE_INTEGER;
        return firstA - firstB || a.displayName.localeCompare(b.displayName);
      });
  }

  async function select(rxcui) {
    const id = clean(rxcui);
    if (!/^\d+$/.test(id)) return null;
    const product = await productForRxcui(id);
    if (!product) return null;
    const ndc = await representativeNdc(id);
    return productParts(product, ndc, ndc ? "representative" : "");
  }

  return { search, select, strengths, verify };
}

const rxNavClient = createRxNavClient();

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") return reply(200, {});
  if (event.httpMethod !== "POST") {
    return reply(405, { success: false, error: "Method Not Allowed" });
  }

  try {
    const body = JSON.parse(event.body || "{}");
    if (!(await verifyUserSession(body.userId, body.sessionToken))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    const action = clean(body.action).toLowerCase();
    if (action === "verify") {
      return reply(200, { success: true, ...(await rxNavClient.verify(body)) });
    }
    if (action === "search") {
      if (clean(body.text).length < 2) {
        return reply(400, { success: false, error: "Enter at least 2 characters" });
      }
      return reply(200, { success: true, results: await rxNavClient.search(body.text) });
    }
    if (action === "strengths") {
      if (clean(body.drug).length < 2) {
        return reply(400, { success: false, error: "A drug name is required" });
      }
      return reply(200, { success: true, results: await rxNavClient.strengths(body.drug) });
    }
    if (action === "select") {
      const result = await rxNavClient.select(body.rxcui);
      if (!result) {
        return reply(404, { success: false, error: "Drug product not found" });
      }
      return reply(200, { success: true, result });
    }
    return reply(400, { success: false, error: "Unknown drug lookup action" });
  } catch (error) {
    const timedOut = error?.name === "AbortError";
    console.error("Drug lookup error:", error?.message || error);
    return reply(timedOut ? 504 : 502, {
      success: false,
      error: timedOut
        ? "The drug database did not respond in time"
        : "The drug database is temporarily unavailable",
    });
  }
};

exports.activeRxcuiFromStatus = activeRxcuiFromStatus;
exports.createRxNavClient = createRxNavClient;
exports.flattenProducts = flattenProducts;
exports.dosageModifiers = dosageModifiers;
exports.productsMatchingName = productsMatchingName;
exports.productParts = productParts;
exports.strengthValues = strengthValues;
