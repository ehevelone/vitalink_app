const QRCode = require("qrcode");

exports.handler = async (event) => {

  console.log("========== QR FUNCTION HIT ==========");
  console.log("EVENT DUMP:", JSON.stringify(event, null, 2));

  try {

    console.log("queryStringParameters:", event.queryStringParameters);
    console.log("rawQuery:", event.rawQuery);
    console.log("path:", event.path);

    let id = null;

    if (event.queryStringParameters && event.queryStringParameters.id) {
      id = event.queryStringParameters.id;
      console.log("ID FROM queryStringParameters:", id);
    } else if (event.rawQuery) {
      const params = new URLSearchParams(event.rawQuery);
      id = params.get("id");
      console.log("ID FROM rawQuery:", id);
    } else {
      console.log("NO QUERY PARAMS FOUND");
    }

    if (!id) {
      console.log("❌ FINAL RESULT: MISSING ID");
      return {
        statusCode: 400,
        body: "Missing QR id"
      };
    }

    console.log("✅ FINAL ID:", id);

    // 🔥 CHANGE IS RIGHT HERE
    const qrData = `https://myvitalink.app/emergency.html?token=${id}`;

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