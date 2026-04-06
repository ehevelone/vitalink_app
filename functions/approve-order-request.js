const db = require("./services/db");
const crypto = require("crypto");

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
    const updateResult = await db.query(
      `
      UPDATE public.order_requests
      SET status = 'approved', approved_at = NOW()
      WHERE id = $1
      RETURNING id
      `,
      [order_id]
    );

    if (!updateResult.rows.length) {
      return reply(500, { success:false, error:"Failed to approve order" });
    }

    // 🔥 PARSE ITEMS
    let parsedItems = [];
    try {
      parsedItems = typeof items === "string"
        ? JSON.parse(items)
        : items;
    } catch {
      parsedItems = [];
    }

    if (!Array.isArray(parsedItems)) {
      parsedItems = [];
    }

    // 🔥 GENERATE TOKENS PER PROFILE
    const qr = [];

    for (let i = 0; i < parsedItems.length; i++) {

      const item = parsedItems[i];

      const profile_id = item.profile_id || null;
      const profile = item.profile || item.profile_name || null;
      const name = item.name || item.product || "Item";

      // 🔐 TOKEN
      const raw_token = crypto.randomBytes(32).toString("hex");
      const token_hash = crypto.createHash("sha256").update(raw_token).digest("hex");

      // 💾 STORE TOKEN
      await db.query(
        `
        INSERT INTO public.qr_tokens
        (order_id, profile_id, raw_token, token_hash, created_at)
        VALUES ($1, $2, $3, $4, NOW())
        `,
        [order_id, profile_id, raw_token, token_hash]
      );

      // 🔗 BUILD URL
      const qr_url = `https://myvitalink.app/emergency.html?token=${raw_token}`;

      qr.push({
        profile_id,
        profile,
        name,
        qr_url
      });
    }

    console.log("✅ TOKENS CREATED:", order_id, qr.length);

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