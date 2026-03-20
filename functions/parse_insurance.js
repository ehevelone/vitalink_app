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

// 🔥 ADD THIS FUNCTION (NO EXISTING CODE TOUCHED)
function fallbackExtractName(rawText) {
  if (!rawText) return "";

  const lines = rawText.split("\n");

  for (const line of lines) {
    const clean = line.trim();

    if (/^[A-Z][a-z]+\s[A-Z][a-z]+/.test(clean)) {
      const lower = clean.toLowerCase();

      if (
        !lower.includes("insurance") &&
        !lower.includes("company") &&
        !lower.includes("hospital") &&
        !lower.includes("benefit") &&
        clean.length < 40
      ) {
        return clean;
      }
    }
  }

  return "";
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

    const response = await client.chat.completions.create({
      model: "gpt-4.1-mini",
      messages: [
        {
          role: "system",
          content: `
You extract structured insurance data from insurance cards and policy documents.

You may receive multiple images belonging to the same policy.
Combine ALL images before extracting.

CRITICAL REQUIREMENT:
You MUST extract the insured person's name.

The insured name may appear as:
- Name
- Insured
- Policyholder
- Member
- Covered Person

SELECTION RULES:
- Choose a HUMAN name only
- NEVER return:
  - doctor names
  - hospital/provider names
  - company names

FALLBACK RULE:
If no label is obvious:
- Select the most prominent full human name
- Prefer name closest to:
  - member ID
  - policy number

FAIL SAFE:
If ANY human name exists → insuredName MUST NOT be empty

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

    let parsed = safeJsonParse(rawContent, { rawText: rawContent });

    if (parsed.rawText) {
      const cleaned = rawContent
        .replace(/```json/gi, "")
        .replace(/```/g, "")
        .trim();

      parsed = safeJsonParse(cleaned, { rawText: rawContent });
    }

    // 🔥 ADD THIS BLOCK (DO NOT REMOVE EXISTING LOGIC)
    let insuredName = (parsed.insuredName || "").toString().trim();

    if (!insuredName && parsed.rawText) {
      insuredName = fallbackExtractName(parsed.rawText);
    }

    const normalized = {
      carrier: (parsed.carrier || "").toString().trim(),
      policy: (parsed.policy || "").toString().trim(),
      memberId: (parsed.memberId || "").toString().trim(),
      group: (parsed.group || "").toString().trim(),
      planType: (parsed.planType || "").toString().trim(),

      // 🔥 REPLACED ONLY THIS LINE (still same variable name)
      insuredName: insuredName,

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