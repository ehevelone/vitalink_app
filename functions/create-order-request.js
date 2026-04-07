const db = require("./services/db");
const admin = require("firebase-admin");
const crypto = require("crypto");

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

  const headers = {
    "Access-Control-Allow-Origin": "https://myvitalink.app",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "POST, OPTIONS"
  };

  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 200,
      headers,
      body: ""
    };
  }

  console.log("🔥 RAW BODY:", event.body);

  try {

    if (!event.body) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ success:false, error: "Missing request body" }),
      };
    }

    let body;
    try {
      body = JSON.parse(event.body);
    } catch {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ success:false, error: "Invalid JSON" }),
      };
    }

    const user_id = body.user_id;
    let items = body.items || body.cart;

    if (!user_id || !items || items.length === 0) {
      return {
        statusCode: 400,
        headers,
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

    // 🔥 BUILD QR DATA
    const qr = items.map(item => {

      const token = crypto.randomBytes(32).toString("hex");

      return {
        profile: item.profile || "Profile",
        profile_id: item.profile_id,
        token: token,
        qr_url: `https://myvitalink.app/emergency.html?token=${token}`
      };
    });

    // 🔥 SAVE TOKENS TO qr_codes TABLE (THIS WAS MISSING)
    for (const q of qr) {
      if (!q.profile_id) continue;

      try {
        await db.query(
          `
          INSERT INTO public.qr_codes (token, profile_id, user_id)
          VALUES ($1, $2, $3)
          `,
          [q.token, q.profile_id, user_id]
        );

        console.log("✅ QR SAVED:", q.token);

      } catch (e) {
        console.error("❌ QR INSERT FAILED:", e);
      }
    }

    // 🧾 SAVE ORDER (WITH QR INCLUDED)
    const result = await db.query(
      `
      INSERT INTO public.order_requests (user_id, items, qr, status)
      VALUES ($1, $2, $3, 'created')
      RETURNING id
      `,
      [user_id, JSON.stringify(items), JSON.stringify(qr)]
    );

    const request_id = result.rows[0].id;

    // 🔥 PUSH IS NOW OPTIONAL (LEFT IN, BUT SAFE)
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

    const tokens = deviceRes.rows.map(r => r.device_token);

    if (tokens.length === 0) {
      console.warn("⚠️ No device tokens — skipping push (OK)");
    } else {

      try {
        await admin.messaging().sendEachForMulticast({
          tokens: tokens,
          notification: {
            title: "VitaLink Order Created",
            body: "Your QR access is ready"
          },
          data: {
            type: "order_ready",
            request_id: request_id.toString()
          },
          android: {
            priority: "high"
          }
        });

        console.log("✅ PUSH SENT");

      } catch (pushErr) {
        console.error("❌ PUSH FAILED:", pushErr);
      }
    }

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: true,
        order_id: request_id
      }),
    };

  } catch (err) {
    console.error("❌ SERVER ERROR:", err);
    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({ success:false, error: "Server error" }),
    };
  }
};