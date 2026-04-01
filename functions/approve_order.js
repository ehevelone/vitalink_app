const db = require("./services/db");
const QRCode = require("qrcode");

exports.handler = async (event) => {

  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 200,
      headers: {
        "Access-Control-Allow-Origin": "https://myvitalink.app",
        "Access-Control-Allow-Headers": "Content-Type",
        "Access-Control-Allow-Methods": "POST, OPTIONS"
      },
      body: ""
    };
  }

  try {

    const body = JSON.parse(event.body || "{}");
    const order_id = body.order_id;

    if (!order_id) {
      return {
        statusCode: 400,
        headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
        body: JSON.stringify({ success:false, error:"Missing order_id" })
      };
    }

    // 🔥 GET ORDER
    const orderRes = await db.query(
      `SELECT id, user_id, items FROM public.order_requests WHERE id=$1 LIMIT 1`,
      [order_id]
    );

    if (orderRes.rows.length === 0) {
      return {
        statusCode: 404,
        headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
        body: JSON.stringify({ success:false, error:"Order not found" })
      };
    }

    const order = orderRes.rows[0];

    // 🔥 GENERATE QR (1 per order for now)
    const qrPayload = JSON.stringify({
      order_id: order.id,
      user_id: order.user_id,
      ts: Date.now()
    });

    const qrImage = await QRCode.toDataURL(qrPayload);

    // 🔥 UPDATE ORDER → APPROVED + STORE QR
    await db.query(
      `
      UPDATE public.order_requests
      SET 
        status = 'approved',
        qr_code = $1,
        approved_at = NOW()
      WHERE id = $2
      `,
      [qrImage, order_id]
    );

    return {
      statusCode: 200,
      headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
      body: JSON.stringify({
        success: true,
        order_id: order_id,
        qr_code: qrImage
      })
    };

  } catch (err) {
    console.error("approve_order error:", err);

    return {
      statusCode: 500,
      headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
      body: JSON.stringify({ success:false, error:"Server error" })
    };
  }
};