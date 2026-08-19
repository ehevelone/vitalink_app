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
You are a medication and supplement label parser.

You MUST return valid JSON only.

Extract and return EXACTLY these fields:

{
  "item_type": "prescription",
  "name": "",
  "dose": "",
  "frequency": "",
  "prescribing_doctor": "",
  "pharmacy": "",
  "pharmacy_phone": "",
  "serving_size": "",
  "active_ingredients": [],
  "other_ingredients": []
}

Rules:

1. Combine information across all images.
2. Do NOT guess.
3. If a field is not visible, return an empty string.
4. item_type must be exactly one of: "prescription", "supplement", "otc", "unknown".
5. Use "prescription" when the label shows Rx number, prescriber, pharmacy, refills, patient directions, or NDC prescription context.
6. Use "supplement" when the label shows Supplement Facts, Dietary Supplement, serving size, suggested use, or botanical/vitamin/mineral ingredients.
7. Use "otc" for non-prescription over-the-counter medications such as aspirin, acetaminophen, ibuprofen, allergy medicine, antacids, or cold medicine.
8. For prescriptions, pharmacy examples include VA, Walmart, CVS, Walgreens, Hy-Vee, Target, etc.
9. pharmacy_phone must be a visible 10-digit phone number.
10. Remove credentials like MD, DO, NP from doctor name.
11. Return medication or supplement name only. Do not include dosage in name.
12. Return prescription dose separately (e.g., "500 mg", "4 mg").
13. Return prescription frequency as written (e.g., "Take 1 tablet twice daily").
14. For supplements, return serving_size exactly as shown, such as "3 capsules".
15. For supplements, active_ingredients should include Supplement Facts items with amount when visible, such as "Ginger Root Extract - 700 mg".
16. For supplements, other_ingredients should include Other Ingredients items when visible.
17. Do not put marketing claims or benefit bullets into active_ingredients.
18. Remove trademark, registered, service mark, and copyright symbols from returned values.
19. No commentary outside JSON.
`
        },
        {
          role: "user",
          content: [
            {
              type: "text",
              text:
                "Extract the medication or supplement details from these label images. Classify whether this is a prescription, supplement, OTC medicine, or unknown."
            },
            ...imageInputs,
          ],
        },
      ],
      response_format: { type: "json_object" },
      max_tokens: 1000,
    });

    const parsed = JSON.parse(response.choices[0].message.content);

    return reply(200, {
      version: "v6-medication-supplement-classifier",
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
