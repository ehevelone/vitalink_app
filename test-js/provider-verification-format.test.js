const test = require("node:test");
const assert = require("node:assert/strict");

const {
  formatPharmacySummary,
  formatProviderSummary,
  verifiedNpi,
} = require("../functions/services/provider-verification-format");
const generateClientReportPdf = require("../functions/generate-client-report-pdf");
const { PDFDocument } = require("pdf-lib");

test("verified provider NPI and primary-care role appear in human output", () => {
  const text = formatProviderSummary({
    name: "Dr. Jane Smith",
    specialty: "Internal Medicine",
    phone: "402-555-1212",
    is_primary_care_provider: true,
    npi: "1234567890",
  });

  assert.match(text, /Internal Medicine/);
  assert.match(text, /Primary Care/);
  assert.match(text, /NPI: 1234567890 \(verified\)/);
});

test("unverified or malformed NPIs never appear in human output", () => {
  const provider = formatProviderSummary({
    name: "Dr. Jane Smith",
    npi: "12345",
    npi_candidates: [{ npi: "1234567890" }],
  });
  const pharmacy = formatPharmacySummary({
    name: "Example Pharmacy",
    npi_candidates: [{ npi: "0987654321" }],
  });

  assert.doesNotMatch(provider, /NPI:/);
  assert.doesNotMatch(pharmacy, /NPI:/);
  assert.equal(verifiedNpi({ npi: "12345" }), "");
});

test("verified pharmacy NPI appears in human output", () => {
  const text = formatPharmacySummary({
    name: "Example Pharmacy",
    phone: "402-555-2323",
    npi: "0987654321",
  });

  assert.match(text, /Example Pharmacy/);
  assert.match(text, /NPI: 0987654321 \(verified\)/);
});

test("client report PDF remains valid with verified provider and pharmacy data", async () => {
  const buffer = await generateClientReportPdf({
    name: "Example Client",
    medications: [{ name: "Example Medication", dose: "10 mg" }],
    pharmacies: [
      { name: "Example Pharmacy", phone: "402-555-2323", npi: "0987654321" },
    ],
    providers: [
      {
        name: "Dr. Jane Smith",
        specialty: "Internal Medicine",
        is_primary_care_provider: true,
        npi: "1234567890",
      },
    ],
  });

  const pdf = await PDFDocument.load(buffer);
  assert.equal(pdf.getPageCount(), 1);
});
