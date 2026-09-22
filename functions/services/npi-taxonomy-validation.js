const db = require("./db");
const { createMailer, fromAddress } = require("./mailer");
const {
  DOCTOR_SPECIALTY_TAXONOMIES,
  NPI_TAXONOMY_MAPPING_RELEASE,
  NPI_TAXONOMY_MAPPING_VERSION,
} = require("./npi-taxonomies");

const NPPES_URL = "https://npiregistry.cms.hhs.gov/api/";
const NUCC_RELEASE_URL =
  "https://www.nucc.org/index.php/code-sets-mainmenu-41/provider-taxonomy-mainmenu-40/csv-mainmenu-57";

function normalize(value) {
  return String(value || "").trim().toLowerCase();
}

function mappedTaxonomies() {
  const seen = new Set();
  const mappings = [];

  for (const [doctorType, taxonomies] of Object.entries(
    DOCTOR_SPECIALTY_TAXONOMIES,
  )) {
    for (const taxonomy of taxonomies) {
      const key = `${taxonomy.code}|${taxonomy.description}`;
      if (seen.has(key)) continue;
      seen.add(key);
      mappings.push({ doctorType, ...taxonomy });
    }
  }

  return mappings;
}

async function fetchWithTimeout(url, fetchImpl, accept) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8000);

  try {
    const response = await fetchImpl(url, {
      headers: { Accept: accept },
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(`Source returned ${response.status}`);
    return response;
  } finally {
    clearTimeout(timeout);
  }
}

async function detectPublishedVersion(fetchImpl = fetch) {
  try {
    const response = await fetchWithTimeout(
      NUCC_RELEASE_URL,
      fetchImpl,
      "text/html",
    );
    const html = await response.text();
    const matches = [...html.matchAll(/Version\s+(\d{2}\.\d+)/gi)].map(
      (match) => match[1],
    );
    return matches[0] || null;
  } catch (error) {
    return null;
  }
}

async function observedTaxonomyCodes(
  description,
  fetchImpl = fetch,
  expectedCodes = [],
) {
  const codes = new Set();
  const expected = new Set(expectedCodes);

  for (let skip = 0; skip <= 800; skip += 200) {
    const params = new URLSearchParams({
      version: "2.1",
      enumeration_type: "NPI-1",
      taxonomy_description: description,
      limit: "200",
      skip: String(skip),
    });
    const response = await fetchWithTimeout(
      `${NPPES_URL}?${params}`,
      fetchImpl,
      "application/json",
    );
    const payload = await response.json();
    const results = payload.results || [];

    for (const result of results) {
      if (result?.basic?.status === "D") continue;
      for (const taxonomy of result.taxonomies || []) {
        if (
          normalize(taxonomy.desc).includes(normalize(description)) &&
          taxonomy.code
        ) {
          codes.add(String(taxonomy.code));
        }
      }
    }

    const foundAllExpected =
      expected.size > 0 && [...expected].every((code) => codes.has(code));
    if (foundAllExpected || results.length < 200 || expected.size === 0) break;
  }

  return [...codes];
}

async function mapWithConcurrency(items, limit, callback) {
  const output = new Array(items.length);
  let nextIndex = 0;

  async function worker() {
    while (nextIndex < items.length) {
      const index = nextIndex++;
      output[index] = await callback(items[index]);
    }
  }

  await Promise.all(
    Array.from({ length: Math.min(limit, items.length) }, () => worker()),
  );
  return output;
}

async function validateTaxonomyMappings(fetchImpl = fetch) {
  const mappings = mappedTaxonomies();
  const descriptions = [...new Set(mappings.map((item) => item.description))];
  const observations = new Map();

  await mapWithConcurrency(descriptions, 4, async (description) => {
    try {
      const expectedCodes = mappings
        .filter((mapping) => mapping.description === description)
        .map((mapping) => mapping.code);
      observations.set(description, {
        codes: await observedTaxonomyCodes(
          description,
          fetchImpl,
          expectedCodes,
        ),
        error: null,
      });
    } catch (error) {
      observations.set(description, {
        codes: [],
        error: error.message || "NPPES validation failed",
      });
    }
  });

  const publishedVersion = await detectPublishedVersion(fetchImpl);
  const results = await mapWithConcurrency(mappings, 4, async (mapping) => {
    const observation = observations.get(mapping.description) || {
      codes: [],
      error: "No validation result",
    };
    const confirmed = observation.codes.includes(mapping.code);

    return {
      ...mapping,
      status: confirmed ? "confirmed" : "review",
      observedCodes: observation.codes,
      note: confirmed
        ? "Code and title observed together in active NPPES records."
        : observation.error ||
          "Code was not observed in the NPPES sample; review manually before changing anything.",
    };
  });
  const reviewCount = results.filter((item) => item.status === "review").length;
  const versionReview =
    Boolean(publishedVersion) && publishedVersion !== NPI_TAXONOMY_MAPPING_VERSION;

  return {
    mappingVersion: NPI_TAXONOMY_MAPPING_VERSION,
    mappingRelease: NPI_TAXONOMY_MAPPING_RELEASE,
    publishedVersion,
    checkedAt: new Date().toISOString(),
    status: reviewCount || versionReview ? "review" : "passed",
    confirmedCount: results.length - reviewCount,
    reviewCount,
    versionReview,
    sourceUrl: NUCC_RELEASE_URL,
    mappings: results,
  };
}

async function ensureValidationTable() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS npi_taxonomy_validation_runs (
      id BIGSERIAL PRIMARY KEY,
      mapping_version TEXT NOT NULL,
      published_version TEXT,
      status TEXT NOT NULL CHECK (status IN ('passed', 'review')),
      trigger_type TEXT NOT NULL CHECK (trigger_type IN ('scheduled', 'manual')),
      checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      confirmed_count INTEGER NOT NULL DEFAULT 0,
      review_count INTEGER NOT NULL DEFAULT 0,
      report JSONB NOT NULL DEFAULT '{}'::jsonb,
      email_sent BOOLEAN NOT NULL DEFAULT false
    )
  `);
  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_npi_taxonomy_validation_runs_checked_at
    ON npi_taxonomy_validation_runs (checked_at DESC)
  `);
}

async function saveValidationRun(report, triggerType) {
  await ensureValidationTable();
  const result = await db.query(
    `
    INSERT INTO npi_taxonomy_validation_runs (
      mapping_version, published_version, status, trigger_type, checked_at,
      confirmed_count, review_count, report
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8::jsonb)
    RETURNING id
    `,
    [
      report.mappingVersion,
      report.publishedVersion,
      report.status,
      triggerType,
      report.checkedAt,
      report.confirmedCount,
      report.reviewCount,
      JSON.stringify(report),
    ],
  );
  return result.rows[0].id;
}

async function markEmailSent(runId) {
  await db.query(
    "UPDATE npi_taxonomy_validation_runs SET email_sent = true WHERE id = $1",
    [runId],
  );
}

async function getLatestValidationRun() {
  await ensureValidationTable();
  const result = await db.query(`
    SELECT id, mapping_version, published_version, status, trigger_type,
           checked_at, confirmed_count, review_count, report, email_sent
    FROM npi_taxonomy_validation_runs
    ORDER BY checked_at DESC
    LIMIT 1
  `);
  return result.rows[0] || null;
}

function emailText(report) {
  const reviewItems = report.mappings.filter((item) => item.status === "review");
  const lines = [
    "VitaLink NPI taxonomy validation",
    "",
    `Result: ${report.status === "passed" ? "PASSED" : "REVIEW REQUIRED"}`,
    `VitaLink mapping: ${report.mappingVersion} (${report.mappingRelease})`,
    `Published version detected: ${report.publishedVersion || "Unable to detect"}`,
    `Confirmed mappings: ${report.confirmedCount}`,
    `Mappings requiring review: ${report.reviewCount}`,
    "",
    "No VitaLink taxonomy mapping was changed automatically.",
  ];

  if (report.versionReview) {
    lines.push(
      "",
      "The published taxonomy version differs from VitaLink's mapped version.",
    );
  }

  if (reviewItems.length) {
    lines.push("", "Review these mappings:");
    for (const item of reviewItems) {
      lines.push(
        `- ${item.doctorType}: ${item.code} / ${item.description} — ${item.note}`,
      );
    }
  }

  lines.push("", `Official release page: ${report.sourceUrl}`);
  return lines.join("\n");
}

async function sendValidationEmail(report) {
  const recipient =
    process.env.NPI_TAXONOMY_ADMIN_EMAIL ||
    process.env.ADMIN_EMAIL ||
    "ehevelone@gmail.com";
  const transporter = createMailer();
  await transporter.sendMail({
    from: fromAddress("VitaLink NPI Validation"),
    to: recipient,
    subject:
      report.status === "passed"
        ? "VitaLink NPI taxonomy validation passed"
        : "VitaLink NPI taxonomy review required",
    text: emailText(report),
  });
  return recipient;
}

module.exports = {
  NUCC_RELEASE_URL,
  detectPublishedVersion,
  emailText,
  ensureValidationTable,
  getLatestValidationRun,
  mappedTaxonomies,
  markEmailSent,
  observedTaxonomyCodes,
  saveValidationRun,
  sendValidationEmail,
  validateTaxonomyMappings,
};
