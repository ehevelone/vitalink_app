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

function normalizeMedicationList(parsed) {
  const rawItems = Array.isArray(parsed?.medications)
    ? parsed.medications
    : parsed?.name || parsed?.dose
      ? [parsed]
      : [];

  const medications = rawItems
    .slice(0, 50)
    .map((item) => ({
      name: clean(item?.name),
      dose: clean(item?.dose),
      frequency: clean(item?.frequency),
      quantity: clean(item?.quantity),
    }))
    .filter((item) => item.name);

  const first = medications[0] || {
    name: "",
    dose: "",
    frequency: "",
    quantity: "",
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
    name: first.name,
    dose: first.dose,
    frequency: first.frequency,
    quantity: first.quantity,
    prescribing_doctor: clean(parsed?.prescribing_doctor),
    pharmacy: clean(parsed?.pharmacy),
    pharmacy_phone: clean(parsed?.pharmacy_phone),
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
        },
      }));
    } else if (body.imageBase64) {
      imageInputs = [{
        type: "image_url",
        image_url: {
          url: `data:image/png;base64,${body.imageBase64}`,
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
  "medications": [
    {
      "name": "",
      "dose": "",
      "frequency": "",
      "quantity": ""
    }
  ],
  "name": "",
  "dose": "",
  "frequency": "",
  "prescribing_doctor": "",
  "pharmacy": "",
  "pharmacy_phone": "",
  "item_type": "prescription",
  "serving_size": "",
  "active_ingredients": [],
  "other_ingredients": []
}

Rules:

1. Combine information across all images of the same label or list.
2. Extract EVERY visible medication row in top-to-bottom order.
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
11. Remove credentials like MD, DO, NP from doctor name.
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
                "Extract every medication row plus any visible prescribing doctor, pharmacy name, and pharmacy phone number. The image may show a prescription bottle, a multi-medication pill-pack manifest, or a supplement / over-the-counter label. Classify item_type."
            },
            ...imageInputs,
          ],
        },
      ],
      response_format: { type: "json_object" },
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
      version: "v7-medication-list-supplements",
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
