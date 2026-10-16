const OpenAI = require("openai");
const { verifyUserSession } = require("./services/user-auth");

const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

function reply(statusCode, obj) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    },
    body: JSON.stringify(obj),
  };
}

function clean(value) {
  return String(value || "").trim();
}

// Prefer the separate first/last fields so the app never has to guess the
// order; fall back to the single printed name.
function prescriberDisplayName(parsed) {
  const first = clean(parsed?.prescribing_doctor_first);
  const last = clean(parsed?.prescribing_doctor_last);
  if (first && last) return `${last}, ${first}`;
  return clean(parsed?.prescribing_doctor);
}

function mergeSingleBottleRows(medications) {
  if (medications.length <= 1) return medications;

  const [medication, ...fragments] = medications;
  const firstValue = (field) =>
    medication[field] || fragments.map((item) => item[field]).find(Boolean) || "";
  const directions = [medication.frequency, ...fragments.map((item) => item.frequency)]
    .filter(Boolean)
    .filter((value, index, values) => values.indexOf(value) === index)
    .join(" ");

  return [{
    ...medication,
    dose: firstValue("dose"),
    form: firstValue("form"),
    ndc: firstValue("ndc"),
    frequency: directions,
    quantity: firstValue("quantity"),
    days_supply: firstValue("days_supply"),
    refills: firstValue("refills"),
    pharmacy_name: firstValue("pharmacy_name"),
    pharmacy_phone: firstValue("pharmacy_phone"),
  }];
}

function normalizeMedicationList(parsed) {
  const rawItems = Array.isArray(parsed?.medications)
    ? parsed.medications
    : parsed?.name || parsed?.dose
      ? [parsed]
      : [];

  let medications = rawItems
    .slice(0, 50)
    .map((item) => ({
      name: clean(item?.name),
      dose: clean(item?.dose),
      form: clean(item?.form),
      ndc: clean(item?.ndc),
      frequency: clean(item?.frequency),
      quantity: clean(item?.quantity),
      days_supply: clean(item?.days_supply),
      refills: clean(item?.refills),
      pharmacy_name: clean(item?.pharmacy_name),
      pharmacy_phone: clean(item?.pharmacy_phone),
    }))
    .filter((item) => item.name);

  const labelFormat = clean(parsed?.label_format).toLowerCase();
  if (labelFormat === "single_bottle") {
    medications = mergeSingleBottleRows(medications);
  }

  const first = medications[0] || {
    name: "",
    dose: "",
    form: "",
    ndc: "",
    frequency: "",
    quantity: "",
    days_supply: "",
    refills: "",
    pharmacy_name: "",
    pharmacy_phone: "",
  };

  const list = (value) =>
    (Array.isArray(value) ? value : [])
      .map(clean)
      .filter(Boolean)
      .slice(0, 60);
  const servingSize = clean(parsed?.serving_size);
  const activeIngredients = list(parsed?.active_ingredients);
  const itemType = classifyItemType({
    aiType: parsed?.item_type,
    pharmacy: clean(parsed?.pharmacy),
    prescribingDoctor: clean(parsed?.prescribing_doctor),
    listRows: medications.length,
    servingSize,
    activeIngredients,
  });

  return {
    medications,
    label_format: labelFormat,
    name: first.name,
    dose: first.dose,
    frequency: first.frequency,
    quantity: first.quantity,
    prescribing_doctor: prescriberDisplayName(parsed),
    pharmacy: clean(parsed?.pharmacy),
    pharmacy_phone: clean(parsed?.pharmacy_phone),
    pharmacy_address: clean(parsed?.pharmacy_address),
    pharmacy_city: clean(parsed?.pharmacy_city),
    pharmacy_state: clean(parsed?.pharmacy_state),
    pharmacy_zip: clean(parsed?.pharmacy_zip),
    // Supplement and OTC labels (restored from the Aug 18 scanner; lost in
    // the Aug 25 overwrite). The app files these under Supplements & OTC.
    item_type: itemType,
    serving_size: servingSize,
    active_ingredients: activeIngredients,
    other_ingredients: list(parsed?.other_ingredients),
  };
}

const SCANNED_ITEM_TYPES = ["prescription", "supplement", "otc"];

// The app never asks the user what a scanned item is, so this always returns
// a type: the AI's answer when valid, otherwise what the label itself shows.
function classifyItemType({
  aiType,
  pharmacy,
  prescribingDoctor,
  listRows,
  servingSize,
  activeIngredients,
}) {
  const type = String(aiType || "").trim().toLowerCase();
  if (SCANNED_ITEM_TYPES.includes(type)) return type;
  if (pharmacy || prescribingDoctor || listRows > 1) return "prescription";
  if (servingSize || activeIngredients.length) return "supplement";
  return "prescription";
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") {
      return reply(200, {});
    }

    if (event.httpMethod !== "POST") {
      return reply(405, {
        success: false,
        error: "Method Not Allowed",
      });
    }

    let body = {};

    try {
      body = event.isBase64Encoded
        ? JSON.parse(Buffer.from(event.body || "", "base64").toString("utf8"))
        : JSON.parse(event.body || "{}");
    } catch {
      return reply(400, {
        success: false,
        error: "Invalid JSON body",
      });
    }

    const authorized = await verifyUserSession(
      body.userId,
      body.sessionToken
    );

    if (!authorized) {
      return reply(403, {
        success: false,
        error: "Unauthorized",
      });
    }

    let imageInputs = [];

    if (body.images && Array.isArray(body.images)) {
      imageInputs = body.images.map(base64 => ({
        type: "image_url",
        image_url: {
          url: `data:image/png;base64,${base64}`,
          // Small curved label print needs the full-resolution image.
          detail: "high",
        },
      }));
    } else if (body.imageBase64) {
      imageInputs = [{
        type: "image_url",
        image_url: {
          url: `data:image/png;base64,${body.imageBase64}`,
          detail: "high",
        },
      }];
    } else if (body.imageUrl) {
      imageInputs = [{
        type: "image_url",
        image_url: { url: body.imageUrl },
      }];
    } else {
      return reply(400, {
        success: false,
        error: "No image provided",
        receivedBody: body,
      });
    }

    const response = await client.chat.completions.create({
      model: "gpt-4.1-mini",
      messages: [
        {
          role: "system",
          content: `
You extract medications from prescription bottles, pharmacy pill-pack manifests,
medication lists, and dispensing labels, and supplement or over-the-counter labels.

You MUST return valid JSON only.

Return exactly this JSON structure:

{
  "label_format": "single_bottle",
  "medications": [
    {
      "name": "",
      "dose": "",
      "form": "",
      "ndc": "",
      "frequency": "",
      "quantity": "",
      "days_supply": "",
      "refills": "",
      "pharmacy_name": "",
      "pharmacy_phone": ""
    }
  ],
  "name": "",
  "dose": "",
  "frequency": "",
  "prescribing_doctor": "",
  "prescribing_doctor_first": "",
  "prescribing_doctor_last": "",
  "pharmacy": "",
  "pharmacy_phone": "",
  "pharmacy_address": "",
  "pharmacy_city": "",
  "pharmacy_state": "",
  "pharmacy_zip": "",
  "item_type": "prescription",
  "serving_size": "",
  "active_ingredients": [],
  "other_ingredients": []
}

Rules:

1. Combine information across all images of the same label or list.
1a. label_format must be exactly one of: "single_bottle", "medication_list",
    "pill_pack", "supplement_label", or "otc_label".
2. A single prescription bottle contains exactly ONE medication. Combine the
   drug name, strength, form, directions, quantity, and refill information into
   that one row even when the curved label separates them visually.
2a. A patient's name, prescriber's name, pharmacy name/address, Rx number, and
    warning text are NEVER medication rows. Do not place them in medications.
2b. For medication_list and pill_pack, extract EVERY visible medication row in
    top-to-bottom order.
3. Preserve repeated rows. Do not merge or deduplicate medications, even when
   the name and strength match, because separate pill-pack rows may be intentional.
4. Do NOT guess, infer, or expand dosing instructions.
5. If strength, frequency, or quantity is not visible for a row, return an empty string.
6. Put medication name only in name and strength only in dose.
7. quantity is the visible dispensed quantity, without inventing units.
8. The legacy top-level name, dose, frequency, and quantity must repeat the first
   medication row, or be empty when no medication is found.
9. Pharmacy examples include VA, Walmart, CVS, Walgreens, Hy-Vee, and independent drugstores.
10. pharmacy_phone must be a visible phone number.
10a. For each medication row, form, ndc, days_supply, refills,
    pharmacy_name, and pharmacy_phone must contain only text clearly visible
    for that row. Return an empty string when it is missing or unclear.
10b. pharmacy_address, pharmacy_city, pharmacy_state, and pharmacy_zip are the
    pharmacy location printed on the label. Never use or infer the patient's
    address. Return an empty string for every part that is not clearly visible.
11. Remove credentials like MD, DO, NP from doctor name.
11a. Also return the prescriber's first name in prescribing_doctor_first and
    last name in prescribing_doctor_last. Pharmacy labels usually print the
    prescriber as "LAST, FIRST"; use the comma to tell which part is which.
    Copy the letters exactly as printed. If any letter is unclear or you cannot
    tell which part is the first name, leave both of these fields empty.
12. item_type must be exactly one of: "prescription", "supplement", "otc".
    Never leave it empty and never answer "unknown"; the app does not ask the
    user, so always choose the best match from the evidence below.
13. "prescription": the label or list shows an Rx number, prescriber or
    "Dr." name, pharmacy name, refills, a patient's name, "Caution: Federal
    law prohibits transfer", or pharmacy-printed directions.
    Pharmacy pill-pack manifests are always "prescription".
14. "supplement": the label has a "Supplement Facts" panel, says "Dietary
    Supplement", lists a serving size or "suggested use", or is a
    vitamin/mineral/botanical/herbal/probiotic/protein product.
15. "otc": the label has a "Drug Facts" panel (required on every US
    over-the-counter medicine) or lists "Active ingredient (in each tablet)"
    with Uses/Warnings, e.g. aspirin, acetaminophen, ibuprofen, allergy,
    antacid, cold, or sleep-aid medicine.
16. If signals conflict, a pharmacy/prescription label wins (a pharmacy can
    dispense an OTC or vitamin by prescription). With no clear signal, choose
    from the product name: a vitamin/herbal name is "supplement", a known
    non-prescription drug is "otc", otherwise "prescription".
17. For supplements, return serving_size exactly as shown, such as "3 capsules".
18. For supplements, active_ingredients lists Supplement Facts items with their
    amount when visible, such as "Ginger Root Extract - 700 mg".
19. For supplements, other_ingredients lists the Other Ingredients when visible.
20. Do not put marketing claims or benefit bullets into active_ingredients.
21. No commentary outside JSON.
`
        },
        {
          role: "user",
          content: [
            {
              type: "text",
              text:
                "Extract every medication row plus any visible NDC, form, days supply, refills, prescribing doctor, pharmacy name, pharmacy phone number, and pharmacy address. The image may show a prescription bottle, a multi-medication pill-pack manifest, or a supplement / over-the-counter label. Classify item_type."
            },
            ...imageInputs,
          ],
        },
      ],
      response_format: { type: "json_object" },
      // Same label, same answer: no creative variation between scans.
      temperature: 0,
      max_tokens: 1800,
    });

    // A very long pill-pack list can exceed max_tokens; the JSON is then cut
    // off and unusable. Tell the app so it can suggest scanning in parts.
    const choice = response.choices[0];
    let raw;
    try {
      raw = JSON.parse(choice.message.content);
    } catch (_) {
      raw = null;
    }
    if (!raw || choice.finish_reason === "length") {
      return reply(422, {
        code: "LIST_TOO_LONG",
        error: "The medication list was too long to read in one photo.",
      });
    }
    const parsed = normalizeMedicationList(raw);

    return reply(200, {
      version: "v8-drug-pharmacy-fields",
      data: parsed,
    });
  } catch (err) {
    console.error("Parse-label error:", err);

    return reply(500, {
      error: err.message,
      details: err.response?.data || null,
    });
  }
};

exports.normalizeMedicationList = normalizeMedicationList;
