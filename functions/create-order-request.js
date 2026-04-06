const db = require("./services/db");
const admin = require("firebase-admin");

/* INIT FIREBASE */
if (!admin.apps.length) {
  try {
    let privateKey = process.env.FIREBASE_PRIVATE_KEY;

    if (privateKey && privateKey.includes("\\n")) {
      privateKey = privateKey.replace(/\\n/g, "\n");
    }

    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: process.env.FIREBASE_PROJECT_ID,
        clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
        privateKey: privateKey
      })
    });

    console.log("✅ Firebase initialized");

  } catch (err) {
    console.error("🔥 Firebase init crash:", err);
    throw err;
  }
}

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

  console.log("🔥 RAW BODY:", event.body);

  try {

    if (!event.body) {
      return {
        statusCode: 400,
        headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
        body: JSON.stringify({ success:false, error: "Missing request body" }),
      };
    }

    let body;
    try {
      body = JSON.parse(event.body);
    } catch {
      return {
        statusCode: 400,
        headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
        body: JSON.stringify({ success:false, error: "Invalid JSON" }),
      };
    }

    const user_id = body.user_id;
    let items = body.items || body.cart;

    if (!user_id || !items || items.length === 0) {
      return {
        statusCode: 400,
        headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
        body: JSON.stringify({ success:false, error: "Missing data" }),
      };
    }

    console.log("🧾 ITEMS RECEIVED:", items);

    // 🔥 LOAD USER PROFILES
    const profileRes = await db.query(
      `
      SELECT id, name
      FROM public.profiles
      WHERE user_id = $1
      `,
      [user_id]
    );

    const profileMap = {};
    profileRes.rows.forEach(p => {
      if (p.name) {
        profileMap[p.name.trim().toLowerCase()] = p.id;
      }
    });

    console.log("👤 PROFILE MAP:", profileMap);

    // 🔥 ENRICH ITEMS WITH profile_id
    items = items.map((item, i) => {

      let profile_id = item.profile_id || null;

      if (!profile_id && item.profile) {
        const key = item.profile.trim().toLowerCase();

        profile_id = profileMap[key] || null;

        if (!profile_id) {
          console.warn(`⚠️ Profile not found for item ${i}:`, item.profile);
        } else {
          console.log(`✅ Matched profile_id for ${item.profile}:`, profile_id);
        }
      }

      return {
        ...item,
        profile_id
      };
    });

    console.log("✅ FINAL ITEMS SAVED:", items);

    // 🧾 SAVE ORDER
    const result = await db.query(
      `
      INSERT INTO public.order_requests (user_id, items, status)
      VALUES ($1, $2, 'pending')
      RETURNING id
      `,
      [user_id, JSON.stringify(items)]
    );

    const request_id = result.rows[0].id;

    // 🔥 DEVICE TOKENS
    const deviceRes = await db.query(
      `
      SELECT device_token
      FROM public.user_devices
      WHERE user_id = $1
        AND device_token IS NOT NULL
        AND LENGTH(device_token) > 20
      ORDER BY updated_at DESC
      `,
      [user_id]
    );

    if (deviceRes.rows.length === 0) {
      console.error("❌ NO DEVICE TOKENS FOUND FOR USER:", user_id);

      return {
        statusCode: 500,
        headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
        body: JSON.stringify({
          success: false,
          error: "No device tokens found — user must open app first"
        }),
      };
    }

    const tokens = deviceRes.rows.map(r => r.device_token);

    console.log("📱 ORDERED TOKENS:", tokens);

    // 🔔 SEND PUSH
    try {

      const response = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: "VitaLink Order Approval",
          body: "Tap to review and approve your accessory order"
        },
        data: {
          type: "order_approval",
          request_id: request_id.toString()
        },
        android: {
          priority: "high"
        }
      });

      console.log("✅ MULTI PUSH SENT:", response);

    } catch (pushErr) {
      console.error("❌ PUSH FAILED:", pushErr);
    }

    return {
      statusCode: 200,
      headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
      body: JSON.stringify({
        success: true,
        order_id: request_id
      }),
    };

  } catch (err) {
    console.error("❌ SERVER ERROR:", err);
    return {
      statusCode: 500,
      headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
      body: JSON.stringify({ success:false, error: "Server error" }),
    };
  }
};