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

    // 🔥 SUPPORT MULTIPLE IMAGES
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
        image_url: {
          url: body.imageUrl,
        },
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
          content:
            "You are a medical label parser. Always respond in valid JSON only, no text outside JSON.",
        },
        {
          role: "user",
          content: [
            {
              type: "text",
              text:
                "Extract details from these medication label images. Combine all visible information and return JSON with keys: name, dose, frequency, prescribing_doctor, pharmacy.",
            },
            ...imageInputs,
          ],
        },
      ],
      response_format: { type: "json_object" },
      max_tokens: 500,
    });

    const parsed = JSON.parse(response.choices[0].message.content);

    return new Response(
      JSON.stringify({
        version: "v4-multi-image",
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