const QRCode = require("qrcode");
const db = require("./services/db");

exports.handler = async (event) => {

  console.log("========== QR FUNCTION HIT ==========");
  console.log("EVENT DUMP:", JSON.stringify(event, null, 2));

  try {

    let id = null;

    if (event.queryStringParameters && event.queryStringParameters.id) {
      id = event.queryStringParameters.id;
      console.log("PROFILE ID:", id);
    } else if (event.rawQuery) {
      const params = new URLSearchParams(event.rawQuery);
      id = params.get("id");
      console.log("PROFILE ID (rawQuery):", id);
    }

    if (!id) {
      return {
        statusCode: 400,
        body: "Missing profile id"
      };
    }

    console.log("✅ FINAL PROFILE ID:", id);

    // 🔍 GET STORED TOKEN
    const profile = await db.query(
      `
      SELECT id, qr_token
      FROM public.profiles
      WHERE id = $1::uuid
      `,
      [id]
    );

    if (profile.rowCount === 0) {
      console.error("❌ PROFILE NOT FOUND");
      return {
        statusCode: 404,
        body: "Profile not found"
      };
    }

    const token = profile.rows[0].qr_token;

    if (!token) {
      console.error("❌ NO TOKEN FOUND ON PROFILE");
      return {
        statusCode: 500,
        body: "QR token missing"
      };
    }

    const qrData = `https://myvitalink.app/emergency.html?token=${token}`;

    console.log("QR DATA:", qrData);

    const qrImage = await QRCode.toBuffer(qrData, {
      type: "png",
      width: 300
    });

    console.log("✅ QR GENERATED SUCCESSFULLY");

    return {
      statusCode: 200,
      headers: {
        "Content-Type": "image/png",
        "Cache-Control": "no-cache"
      },
      body: qrImage.toString("base64"),
      isBase64Encoded: true
    };

  } catch (err) {
    console.error("🔥 QR ERROR:", err);

    return {
      statusCode: 500,
      body: "QR generation failed"
    };
  }
};