import OpenAI from "openai";

const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

export default async (req) => {
  try {
    const raw = await req.text();
    let body = {};

    try {
      body = JSON.parse(raw);
    } catch {
      console.error("Invalid JSON body:", raw);
    }

    // ---- MULTI IMAGE SUPPORT ----
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
      return new Response(
        JSON.stringify({
          error: "No image provided",
          receivedBody: body,
        }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const response = await client.chat.completions.create({
      model: "gpt-4.1-mini",
      messages: [
        {
          role: "system",
          content: `
You are a prescription bottle label parser.

You MUST return valid JSON only.

Extract and return EXACTLY these fields:

{
  "name": "",
  "dose": "",
  "frequency": "",
  "prescribing_doctor": "",
  "pharmacy": "",
  "pharmacy_phone": ""
}

Rules:

1. Combine information across all images.
2. Do NOT guess.
3. If a field is not visible, return an empty string.
4. Pharmacy examples: VA, Walmart, CVS, Walgreens, Hy-Vee, Target, etc.
5. pharmacy_phone must be a visible 10-digit phone number.
6. Remove credentials like MD, DO, NP from doctor name.
7. Return medication name only (no dosage in name).
8. Return dose separately (e.g., "500 mg", "4 mg").
9. Return frequency as written (e.g., "Take 1 tablet twice daily").
10. No commentary outside JSON.
`
        },
        {
          role: "user",
          content: [
            {
              type: "text",
              text:
                "Extract medication, prescribing doctor, pharmacy name, and pharmacy phone number from these prescription bottle images."
            },
            ...imageInputs,
          ],
        },
      ],
      response_format: { type: "json_object" },
      max_tokens: 700,
    });

    const parsed = JSON.parse(response.choices[0].message.content);

    return new Response(
      JSON.stringify({
        version: "v5-multi-image-pharmacy-phone",
        data: parsed,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );

  } catch (err) {
    console.error("Parse-label error:", err);

    return new Response(
      JSON.stringify({
        error: err.message,
        details: err.response?.data || null,
      }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
};