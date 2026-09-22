function clean(value) {
  return String(value ?? "").trim();
}

function verifiedNpi(item) {
  const npi = clean(item?.npi);
  return /^\d{10}$/.test(npi) ? npi : "";
}

function isPrimaryCareProvider(item) {
  return item?.is_primary_care_provider === true ||
    item?.isPrimaryCareProvider === true;
}

function formatProviderSummary(provider) {
  const details = [];
  const specialty = clean(provider?.specialty);
  const clinic = clean(provider?.clinic);
  const phone = clean(provider?.phone);
  const npi = verifiedNpi(provider);

  if (specialty) details.push(specialty);
  if (isPrimaryCareProvider(provider)) details.push("Primary Care");
  if (clinic) details.push(clinic);
  if (phone) details.push(phone);
  if (npi) details.push(`NPI: ${npi} (verified)`);

  return [clean(provider?.name) || "Unknown", ...details].join(" - ");
}

function formatPharmacySummary(pharmacy) {
  const details = [];
  const phone = clean(pharmacy?.phone);
  const extra = clean(pharmacy?.details);
  const npi = verifiedNpi(pharmacy);

  if (phone) details.push(phone);
  if (extra) details.push(extra);
  if (npi) details.push(`NPI: ${npi} (verified)`);

  return [clean(pharmacy?.name) || "Unknown", ...details].join(" - ");
}

module.exports = {
  formatPharmacySummary,
  formatProviderSummary,
  isPrimaryCareProvider,
  verifiedNpi,
};
