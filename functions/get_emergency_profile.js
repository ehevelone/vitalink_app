exports.handler = async () => {
  return {
    statusCode: 410,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "https://myvitalink.app",
    },
    body: JSON.stringify({
      success: false,
      error: "This legacy emergency profile endpoint has been disabled.",
    }),
  };
};
