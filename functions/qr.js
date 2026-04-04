const QRCode = require("qrcode");

exports.handler = async (event) => {

  try {

    const path = event.path || "";
    const id = path.split("/qr/")[1];

    if (!id) {
      return {
        statusCode: 400,
        body: "Missing QR id"
      };
    }

    // 🔥 THIS is what the QR contains
    const qrData = `vitalink://profile/${id}`;

    const qrImage = await QRCode.toBuffer(qrData, {
      type: "png",
      width: 300
    });

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
    console.error("QR ERROR:", err);

    return {
      statusCode: 500,
      body: "QR generation failed"
    };
  }
};