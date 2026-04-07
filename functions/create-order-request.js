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

// 🔐 HASH FUNCTION
function hashToken(token) {
  return crypto.createHash("sha256").update(token).digest("hex");
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

    console.log("✅ FINAL ITEMS:", items);

    // 🔥 BUILD QR DATA + SAVE TO PROFILES
    const qr = [];

    for (const item of items) {

      if (!item.profile_id) continue;

      const rawToken = crypto.randomBytes(32).toString("hex");
      const tokenHash = hashToken(rawToken);

      // ✅ SAVE DIRECTLY TO PROFILES
      await db.query(
        `
        UPDATE public.profiles
        SET 
          qr_token = $1,
          token_hash = $2,
          qr_created_at = NOW(),
          qr_revoked = false
        WHERE id = $3 AND user_id = $4
        `,
        [rawToken, tokenHash, item.profile_id, user_id]
      );

      const qr_url = `https://myvitalink.app/emergency.html?token=${rawToken}`;

      qr.push({
        profile: item.profile || "Profile",
        profile_id: item.profile_id,
        qr_url
      });

      console.log("✅ QR SAVED TO PROFILE:", item.profile_id);
    }

    // 🧾 SAVE ORDER
    const result = await db.query(
      `
      INSERT INTO public.order_requests (user_id, items, qr, status)
      VALUES ($1, $2, $3, 'created')
      RETURNING id
      `,
      [user_id, JSON.stringify(items), JSON.stringify(qr)]
    );

    const request_id = result.rows[0].id;

    // 🔔 PUSH (UNCHANGED)
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

    if (tokens.length > 0) {
      try {
        await admin.messaging().sendEachForMulticast({
          tokens,
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