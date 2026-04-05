const db = require("./services/db");

exports.handler = async (event) => {

  // ✅ FULL CORS FIX
  const headers = {
    "Access-Control-Allow-Origin": "https://myvitalink.app",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Allow-Methods": "POST, OPTIONS"
  };

  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 200,
      headers,
      body: ""
    };
  }

  try {

    let body = {};

    try {
      body = JSON.parse(event.body || "{}");
    } catch (e) {
      body = {};
    }

    const order_id = body.order_id || body.request_id;

    let result;

    if (order_id) {

      result = await db.query(
        `
        SELECT id, items, status
        FROM public.order_requests
        WHERE id = $1
        LIMIT 1
        `,
        [order_id]
      );

    } else {

      result = await db.query(
        `
        SELECT id, items, status
        FROM public.order_requests
        WHERE status = 'pending'
        ORDER BY id DESC
        `
      );
    }

    if (!result || !result.rows || result.rows.length === 0) {
      return {
        statusCode: 200,
        headers,
        body: JSON.stringify({ success: true, orders: [] })
      };
    }

    const orders = result.rows.map(order => {

      let rawItems = [];

      try {
        rawItems = typeof order.items === "string"
          ? JSON.parse(order.items)
          : order.items;
      } catch (e) {
        rawItems = [];
      }

      // ✅ KEEP profile_id
      const items = (rawItems || []).map(i => ({
        product: i.name || i.product || "Unknown",
        profile_name: i.profile || i.profile_name || "Unknown",
        profile_id: i.profile_id || null
      }));

      // ✅ REAL QR (NO FAKE / NO FUNCTION)
      const qr = (items || []).map((item, i) => ({
        id: `${order.id}-${i}`,
        profile: item.profile_name,
        name: item.product,
        qr_url: item.profile_id
          ? `https://myvitalink.app/emergency/${item.profile_id}`
          : null
      }));

      return {
        id: order.id,
        status: order.status,
        items: items,
        qr: qr
      };
    });

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: true,
        orders: orders
      })
    };

  } catch (err) {
    console.error("get_pending_orders error:", err);

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: false,
        orders: []
      })
    };
  }
};