const assert = require("node:assert/strict");
const test = require("node:test");

const generateClientReportPdf = require("../generate-client-report-pdf");

test("the client report PDF builds with prescriptions and supplements", async () => {
  const pdf = await generateClientReportPdf({
    name: "Pat Client",
    medications: [
      { name: "Lisinopril", dose: "10 mg", frequency: "Daily", itemType: "prescription" },
      {
        name: "Ginger Root",
        itemType: "supplement",
        servingSize: "3 capsules",
        activeIngredients: ["Ginger Root Extract - 700 mg"],
        otherIngredients: ["Gelatin"],
      },
    ],
    providers: [],
  });
  assert.ok(pdf && pdf.length > 500, "a PDF was produced");
});
