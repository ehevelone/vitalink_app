const { createRxNavClient } = require("../drug_lookup");

const checks = [
  ["amlodipine", "5 mg", "tablet"],
  ["atorvastatin", "20 mg", "tablet"],
  ["lisinopril", "10 mg", "tablet"],
  ["losartan", "50 mg", "tablet"],
  ["metformin", "500 mg", "tablet"],
  ["metformin ER", "500 mg", "tablet"],
  ["levothyroxine", "25 mcg", "tablet"],
  ["omeprazole", "40 mg", "capsule"],
  ["pantoprazole", "40 mg", "tablet"],
  ["simvastatin", "40 mg", "tablet"],
  ["rosuvastatin", "20 mg", "tablet"],
  ["gabapentin", "300 mg", "capsule"],
  ["hydrochlorothiazide", "25 mg", "tablet"],
  ["furosemide", "20 mg", "tablet"],
  ["metoprolol succinate ER", "50 mg", "tablet"],
  ["metoprolol tartrate", "25 mg", "tablet"],
  ["carvedilol", "25 mg", "tablet"],
  ["tamsulosin", "0.4 mg", "capsule"],
  ["sertraline", "50 mg", "tablet"],
  ["escitalopram", "10 mg", "tablet"],
  ["trazodone", "50 mg", "tablet"],
  ["donepezil", "10 mg", "tablet"],
  ["montelukast", "10 mg", "tablet"],
  ["clopidogrel", "75 mg", "tablet"],
  ["Eliquis", "5 mg", "tablet"],
  ["Xarelto", "20 mg", "tablet"],
  ["Jardiance", "10 mg", "tablet"],
  ["Farxiga", "10 mg", "tablet"],
  ["Ozempic", "0.25 mg", "injection"],
  ["insulin glargine", "100 unit/ml", "injection"],
  ["prednisone", "10 mg", "tablet"],
  ["allopurinol", "100 mg", "tablet"],
  ["meloxicam", "15 mg", "tablet"],
  ["finasteride", "5 mg", "tablet"],
  ["potassium chloride ER", "10 mEq", "tablet"],
  ["vitamin D", "50000 unit", "capsule"],
  ["albuterol", "90 mcg", "inhaler"],
  ["fluticasone", "50 mcg", "nasal spray"],
  ["latanoprost", "0.005%", "ophthalmic solution"],
  ["duloxetine", "30 mg", "capsule"],
];

async function main() {
  const client = createRxNavClient();
  for (const [name, dose, form] of checks) {
    try {
      const result = await client.verify({ name, dose, form });
      const match = result.match?.displayName || "";
      console.log(`${name} ${dose}: ${result.status}${match ? ` -> ${match}` : ""}`);
    } catch (error) {
      console.log(`${name} ${dose}: error -> ${error.message}`);
    }
    await new Promise((resolve) => setTimeout(resolve, 150));
  }

  console.log("--- search -> strengths ---");
  for (const name of [
    "metoprolol succinate",
    "insulin glargine",
    "ozempic",
    "albuterol",
    "albuterol sulfate",
    "Advair",
    "Symbicort",
    "Breo",
    "Spiriva",
    "Trelegy",
    "fluticasone/salmeterol",
    "potassium chloride",
    "vitamin d",
    "latanoprost",
  ]) {
    try {
      const searchResults = await client.search(name);
      const options = await client.strengths(name);
      const top = options.slice(0, 5).map((option) => option.displayName).join(" | ");
      const inhalerIndex = options.findIndex((option) =>
        /(?:inhaler|inhalation (?:aerosol|powder))/i.test(option.displayName),
      );
      console.log(
        `${name}: search=${searchResults.length} strengths=${options.length}` +
          ` inhaler=${inhalerIndex >= 0 ? inhalerIndex + 1 : "none"}` +
          `${top ? ` -> ${top}` : ""}`,
      );
    } catch (error) {
      console.log(`${name}: error -> ${error.message}`);
    }
    await new Promise((resolve) => setTimeout(resolve, 150));
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}

module.exports = { checks, main };
