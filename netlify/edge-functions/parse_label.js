export default async () => {
  return new Response(
    JSON.stringify({
      success: false,
      error: "This legacy edge parser has been disabled.",
    }),
    {
      status: 410,
      headers: { "Content-Type": "application/json" },
    }
  );
};
