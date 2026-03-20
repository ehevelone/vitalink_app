const OpenAI = require("openai");

// ✅ OpenAI client
const client = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

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

function safeJsonParse(value, fallback = {}) {
  try {
    return JSON.parse(value);
  } catch (_) {
    return fallback;
  }
}

function normalizeBenefits(input) {
  if (!Array.isArray(input)) return [];

  const finalBenefits = input
    .map((item) => {
      if (!item || typeof item !== "object") return null;

      const name = (item.name || "").toString().trim();
      const value = (item.value || "").toString().trim();

      if (!name || !value) return null;

      return { name, value };
    })
    .filter(Boolean);

  // 🔁 Deduplicate
  const seen = new Set();
  const deduped = [];

  for (const benefit of finalBenefits) {
    const key = `${benefit.name.toLowerCase()}|${benefit.value.toLowerCase()}`;
    if (seen.has(key)) continue;
    seen.add(key);
    deduped.push(benefit);
  }

  return deduped;
}

exports.handler = async (event) => {
  try {
    // ✅ CORS preflight
    if (event.httpMethod === "OPTIONS") {
      return reply(200, {});
    }

    // ✅ Enforce POST
    if (event.httpMethod !== "POST") {
      return reply(405, {
        success: false,
        error: "Method Not Allowed",
      });
    }

    // ✅ Safe body parsing
    let body = {};
    try {
      if (event.isBase64Encoded) {
        body = JSON.parse(
          Buffer.from(event.body || "", "base64").toString("utf8")
        );
      } else {
        body = JSON.parse(event.body || "{}");
      }
    } catch (e) {
      return reply(400, {
        success: false,
        error: "Invalid JSON body",
      });
    }

    // ✅ Build image input (multi + fallback support)
    const contentParts = [
      {
        type: "text",
        text: "Extract insurance policy details and benefits.",
      },
    ];

    if (Array.isArray(body.images) && body.images.length > 0) {
      for (const img of body.images) {
        if (!img) continue;
        contentParts.push({
          type: "image_url",
          image_url: {
            url: `data:image/png;base64,${img}`,
          },
        });
      }
    } else if (body.imageBase64) {
      contentParts.push({
        type: "image_url",
        image_url: {
          url: `data:image/png;base64,${body.imageBase64}`,
        },
      });
    } else if (body.imageUrl) {
      contentParts.push({
        type: "image_url",
        image_url: {
          url: body.imageUrl,
        },
      });
    } else {
      return reply(400, {
        success: false,
        error: "No image provided",
      });
    }

    // ✅ OpenAI call
    const response = await client.chat.completions.create({
      model: "gpt-4.1-mini",
      messages: [
        {
          role: "system",
          content: `
You extract structured insurance data from insurance cards and policy documents.

You may receive multiple images belonging to the same policy.
Combine ALL images before extracting.

Return ONLY valid JSON with EXACTLY this structure:

{
  "carrier": "",
  "policy": "",
  "memberId": "",
  "group": "",
  "planType": "",
  "insuredName": "",
  "beneficiary": "",
  "benefits": [
    { "name": "", "value": "" }
  ],
  "notes": ""
}

FIELD RULES:
- carrier = insurance company
- policy = policy/certificate number
- memberId = member ID
- group = group number if present
- planType = type of plan if shown
- insuredName = person covered by policy
- beneficiary = listed beneficiary if present

BENEFITS RULES:
- Extract ALL benefit payouts and coverage items
- Each benefit must have:
  - name (short, clean label)
  - value (dollar amount, %, or description)

NAMING RULES:
- Keep original meaning
- Lightly shorten wording
- DO NOT over-generalize

GOOD:
- "Daily Confinement"
- "Hospital Admission"
- "ICU Daily"
- "Emergency Room"
- "Surgery"

BAD:
- "Hospital"
- "Coverage"
- "Medical"

OTHER RULES:
- Do not duplicate benefits
- If not found → return ""
- If no benefits → return []
- Do NOT explain
- Do NOT wrap in markdown
          `.trim(),
        },
        {
          role: "user",
          content: contentParts,
        },
      ],
      max_tokens: 1200,
    });

    const rawContent = response.choices?.[0]?.message?.content || "";

    // ✅ Parse AI output
    let parsed = safeJsonParse(rawContent, { rawText: rawContent });

    if (parsed.rawText) {
      const cleaned = rawContent
        .replace(/```json/gi, "")
        .replace(/```/g, "")
        .trim();

      parsed = safeJsonParse(cleaned, { rawText: rawContent });
    }

    // ✅ Normalize output
    const normalized = {
      carrier: (parsed.carrier || "").toString().trim(),
      policy: (parsed.policy || "").toString().trim(),
      memberId: (parsed.memberId || "").toString().trim(),
      group: (parsed.group || "").toString().trim(),
      planType: (parsed.planType || "").toString().trim(),

      insuredName: (parsed.insuredName || "").toString().trim(),
      beneficiary: (parsed.beneficiary || "").toString().trim(),

      benefits: normalizeBenefits(parsed.benefits),
      notes: (parsed.notes || "").toString().trim(),
    };

    return reply(200, {
      success: true,
      data: normalized,
    });

  } catch (err) {
    console.error("❌ parse_insurance error:", err);
    return reply(500, {
      success: false,
      error: "Server error",
      details: err.message,
    });
  }
};