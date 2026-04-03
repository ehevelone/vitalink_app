const db = require("./services/db");

const reply = (statusCode, obj) => ({
  statusCode,
  headers: {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "https://myvitalink.app",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  },
  body: JSON.stringify(obj),
});

exports.handler = async (event) => {

  if (event.httpMethod === "OPTIONS") {
    return reply(200, {});
  }

  try {

    let body = {};
    try {
      body = JSON.parse(event.body || "{}");
    } catch {}

    const order_id = body.order_id || body.request_id;

    if (!order_id) {
      return reply(400, { success:false, error:"Missing order_id" });
    }

    // 🔥 GET ORDER
    const result = await db.query(
      `
      SELECT items
      FROM public.order_requests
      WHERE id = $1
      LIMIT 1
      `,
      [order_id]
    );

    if (!result.rows.length) {
      return reply(404, { success:false, error:"Order not found" });
    }

    const { items } = result.rows[0];

    // 🔥 APPROVE ORDER
    await db.query(
      `
      UPDATE public.order_requests
      SET status = 'approved', approved_at = NOW()
      WHERE id = $1
      `,
      [order_id]
    );

    // 🔥 PARSE ITEMS
    let parsedItems = [];
    try {
      parsedItems = typeof items === "string"
        ? JSON.parse(items)
        : items;
    } catch {
      parsedItems = [];
    }

    // 🔥 BUILD QR DATA PER PROFILE
    const qr = parsedItems.map((item, i) => ({
      id: `${order_id}-${i}`,
      profile: item.profile || null,
      name: item.name,
      qr_url: `https://myvitalink.app/qr/${order_id}-${i}`
    }));

    console.log("✅ APPROVED + QR BUILT:", order_id);

    return reply(200, {
      success: true,
      order_id,
      qr
    });

  } catch (err) {
    console.error("❌ approve_order error:", err);
    return reply(500, { success:false, error:"Server error" });
  }
};