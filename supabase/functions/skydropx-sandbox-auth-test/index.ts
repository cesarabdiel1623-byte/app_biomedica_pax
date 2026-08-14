const JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: JSON_HEADERS,
  });
}

Deno.serve(async (request: Request): Promise<Response> => {
  // CORS Preflight
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: JSON_HEADERS });
  }

  // 405 Method Not Allowed for non-POST requests
  if (request.method !== "POST") {
    return jsonResponse({ ok: false, error: "method_not_allowed" }, 405);
  }

  try {
    // 1. Read required secrets from environment
    const clientId = Deno.env.get("SKYDROPX_SANDBOX_CLIENT_ID")?.trim();
    const clientSecret = Deno.env.get("SKYDROPX_SANDBOX_CLIENT_SECRET")?.trim();
    const rawBaseUrl = Deno.env.get("SKYDROPX_SANDBOX_BASE_URL")?.trim() || "https://sb-pro.skydropx.com";

    if (!clientId || !clientSecret) {
      return jsonResponse(
        {
          ok: false,
          environment: "sandbox",
          token_received: false,
          error: "missing_configuration",
          message: "Required SkyDropX Sandbox secrets are not configured in environment.",
        },
        500,
      );
    }

    const baseUrl = rawBaseUrl.replace(/\/+$/, "");
    const oauthEndpoint = `${baseUrl}/api/v1/oauth/token`;

    // 2. Prepare OAuth client_credentials request body
    const bodyParams = new URLSearchParams();
    bodyParams.append("grant_type", "client_credentials");
    bodyParams.append("client_id", clientId);
    bodyParams.append("client_secret", clientSecret);

    // 3. Setup timeout controller (10s)
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 10000);

    let skydropxRes: Response;
    try {
      skydropxRes = await fetch(oauthEndpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "Accept": "application/json",
        },
        body: bodyParams.toString(),
        signal: controller.signal,
      });
    } catch (err: unknown) {
      clearTimeout(timeoutId);
      const isAbort = err instanceof Error && err.name === "AbortError";
      return jsonResponse(
        {
          ok: false,
          environment: "sandbox",
          token_received: false,
          error: isAbort ? "request_timeout" : "network_error",
          message: isAbort
            ? "Connection to SkyDropX Sandbox timed out (10s)."
            : "Network error attempting to reach SkyDropX Sandbox OAuth endpoint.",
        },
        isAbort ? 504 : 502,
      );
    }

    clearTimeout(timeoutId);

    // 4. Parse SkyDropX response
    const rawText = await skydropxRes.text();
    let data: Record<string, unknown> = {};
    try {
      data = JSON.parse(rawText);
    } catch (_) {
      // Non-JSON response handling
    }

    if (!skydropxRes.ok) {
      return jsonResponse(
        {
          ok: false,
          environment: "sandbox",
          token_received: false,
          status_code: skydropxRes.status,
          error: "skydropx_auth_error",
          message: typeof data.message === "string"
            ? data.message
            : typeof data.error === "string"
            ? data.error
            : `SkyDropX returned HTTP ${skydropxRes.status}`,
        },
        skydropxRes.status >= 500 ? 502 : skydropxRes.status,
      );
    }

    const accessToken = typeof data.access_token === "string" ? data.access_token : null;

    if (!accessToken) {
      return jsonResponse(
        {
          ok: false,
          environment: "sandbox",
          token_received: false,
          error: "invalid_token_response",
          message: "SkyDropX returned HTTP 200 but access_token was not found in response.",
        },
        502,
      );
    }

    // 5. Secure success response - NEVER return access_token to client or write to logs
    return jsonResponse(
      {
        ok: true,
        environment: "sandbox",
        token_received: true,
        token_type: typeof data.token_type === "string" ? data.token_type : "Bearer",
        expires_in: typeof data.expires_in === "number" ? data.expires_in : null,
        scope: typeof data.scope === "string" ? data.scope : null,
      },
      200,
    );
  } catch (error: unknown) {
    return jsonResponse(
      {
        ok: false,
        environment: "sandbox",
        token_received: false,
        error: "internal_server_error",
        message: error instanceof Error ? error.message : "An unexpected error occurred.",
      },
      500,
    );
  }
});
