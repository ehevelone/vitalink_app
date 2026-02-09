import OpenAI from "openai";

// Initialize OpenAI client
const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

export default async (req) => {
  try {
    // ✅ Parse body safely
    const raw = await req.text();
    let body = {};
    try {
      body = JSON.parse(raw);
    } catch {
      console.error("Invalid JSON body:", raw);
    }

    // ✅ Ensure we have either imageUrl or imageBase64
    let imageInput;
    if (body.imageUrl) {
      imageInput = { type: "image_url", image_url: { url: body.imageUrl } };
    } else if (body.imageBase64) {
      imageInput = {
        type: "image_url",
        image_url: { url: `data:image/png;base64,${body.imageBase64}` },
      };
    } else {
      return new Response(
        JSON.stringify({
          error: "No image provided (need imageUrl or imageBase64)",
          receivedBody: body,
        }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // ✅ Call OpenAI Vision
    const response = await client.chat.completions.create({
      model: "gpt-4.1-mini", // Vision-capable
      messages: [
        {
          role: "system",
          content:
            "You are a medical label parser. Always respond in valid JSON only, no text outside JSON.",
        },
        {
          role: "user",
          content: [
            {
              type: "text",
              text: "Extract details from this medication label. Return JSON with keys: name, dose, frequency, prescribing_doctor, pharmacy.",
            },
            imageInput,
          ],
        },
      ],
      response_format: { type: "json_object" },
      max_tokens: 500,
    });

    const parsed = JSON.parse(response.choices[0].message.content);

    return new Response(
      JSON.stringify({
        version: "v3-json-strict",
        data: parsed,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("Parse-label error:", err);
    return new Response(
      JSON.stringify({
        error: err.message,
        receivedBody: {},
        details: err.response?.data || null,
      }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
};
