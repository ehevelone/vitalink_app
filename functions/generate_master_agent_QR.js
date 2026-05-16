// functions/generateMasterAgentQR.js
const QRCode = require("qrcode");
const { requireAdmin } = require("./_adminAuth");

exports.handler = async (event) => {
  try {
    const auth = await requireAdmin(event);

    if (auth.error) {
      return {
        statusCode: 401,
        body: JSON.stringify({ success: false, error: "Unauthorized" }),
      };
    }

    // 🔑 This is the static payload the app looks for when scanning
    const masterPayload = "agent_master";

    // Generate QR as base64 PNG
    const qrDataUrl = await QRCode.toDataURL(masterPayload);

    return {
      statusCode: 200,
      body: JSON.stringify({
        success: true,
        payload: masterPayload,
        qr: qrDataUrl, // base64 image string
      }),
    };
  } catch (err) {
    console.error("Error generating master agent QR:", err);
    return {
      statusCode: 500,
      body: JSON.stringify({ success: false, error: "Server error" }),
    };
  }
};
