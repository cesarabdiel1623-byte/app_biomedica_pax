const JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type JsonRecord = Record<string, unknown>;

type ValidAddress = {
  country_code: "MX";
  postal_code: string;
  area_level1: string;
  area_level2: string;
  area_level3: string;
};

type ValidParcel = {
  length: number;
  width: number;
  height: number;
  weight: number;
};

type ValidQuotationRequest = {
  address_from: ValidAddress;
  address_to: ValidAddress;
  parcels: ValidParcel[];
};

function jsonResponse(body: JsonRecord, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: JSON_HEADERS,
  });
}

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requireNonEmptyString(
  source: JsonRecord,
  key: string,
  path: string,
): string {
  const value = source[key];
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${path}.${key}_required`);
  }
  return value.trim();
}

function validateAddress(value: unknown, path: string): ValidAddress {
  if (!isRecord(value)) {
    throw new Error(`${path}_required`);
  }

  const countryCode = requireNonEmptyString(value, "country_code", path)
    .toUpperCase();
  if (countryCode !== "MX") {
    throw new Error(`${path}.country_code_must_be_mx`);
  }

  return {
    country_code: "MX",
    postal_code: requireNonEmptyString(value, "postal_code", path),
    area_level1: requireNonEmptyString(value, "area_level1", path),
    area_level2: requireNonEmptyString(value, "area_level2", path),
    area_level3: requireNonEmptyString(value, "area_level3", path),
  };
}

function requirePositiveNumber(
  source: JsonRecord,
  key: string,
  path: string,
): number {
  const value = source[key];
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    throw new Error(`${path}.${key}_must_be_positive_number`);
  }
  return value;
}

function validateParcels(value: unknown): ValidParcel[] {
  if (!Array.isArray(value) || value.length === 0) {
    throw new Error("parcels_must_be_non_empty_array");
  }

  return value.map((parcel, index) => {
    const path = `parcels[${index}]`;
    if (!isRecord(parcel)) {
      throw new Error(`${path}_must_be_object`);
    }
    return {
      length: requirePositiveNumber(parcel, "length", path),
      width: requirePositiveNumber(parcel, "width", path),
      height: requirePositiveNumber(parcel, "height", path),
      weight: requirePositiveNumber(parcel, "weight", path),
    };
  });
}

function validateBody(body: unknown): ValidQuotationRequest {
  if (!isRecord(body)) {
    throw new Error("body_must_be_object");
  }

  return {
    address_from: validateAddress(body.address_from, "address_from"),
    address_to: validateAddress(body.address_to, "address_to"),
    parcels: validateParcels(body.parcels),
  };
}

function safeStatus(status: number): number {
  if (
    status === 400 ||
    status === 401 ||
    status === 403 ||
    status === 404 ||
    status === 422 ||
    status === 429
  ) {
    return status;
  }
  if (status >= 500) return 502;
  return 502;
}

async function sleep(ms: number): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchWithTimeout(
  url: string,
  init: RequestInit,
  timeoutMs: number,
): Promise<Response> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, {
      ...init,
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timeoutId);
  }
}

async function parseJsonResponse(response: Response): Promise<unknown> {
  const rawText = await response.text();
  try {
    return JSON.parse(rawText);
  } catch (_) {
    throw new Error("invalid_json_response");
  }
}

async function getSandboxAccessToken(baseUrl: string): Promise<string> {
  const clientId = Deno.env.get("SKYDROPX_SANDBOX_CLIENT_ID")?.trim();
  const clientSecret = Deno.env.get("SKYDROPX_SANDBOX_CLIENT_SECRET")?.trim();

  if (!clientId || !clientSecret) {
    throw new Error("missing_oauth_configuration");
  }

  const bodyParams = new URLSearchParams();
  bodyParams.append("grant_type", "client_credentials");
  bodyParams.append("client_id", clientId);
  bodyParams.append("client_secret", clientSecret);

  const response = await fetchWithTimeout(
    `${baseUrl}/api/v1/oauth/token`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "application/json",
      },
      body: bodyParams.toString(),
    },
    10000,
  );

  const data = await parseJsonResponse(response);

  if (!response.ok) {
    throw new Error(`oauth_http_${response.status}`);
  }

  if (
    !isRecord(data) ||
    typeof data.access_token !== "string" ||
    data.access_token.trim() === ""
  ) {
    throw new Error("invalid_oauth_token_response");
  }

  return data.access_token;
}

function getString(source: JsonRecord, key: string): string | null {
  const value = source[key];
  if (typeof value === "string") return value;
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  return null;
}

function getNumber(source: JsonRecord, key: string): number | null {
  const value = source[key];
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function sanitizeRates(rawRates: unknown): JsonRecord[] {
  if (!Array.isArray(rawRates)) return [];

  return rawRates
    .filter(isRecord)
    .map((rate) => {
      return {
        id: getString(rate, "id"),
        provider_name: getString(rate, "provider_name"),
        provider_display_name: getString(rate, "provider_display_name"),
        provider_service_name: getString(rate, "provider_service_name"),
        provider_service_code: getString(rate, "provider_service_code"),
        status: getString(rate, "status"),
        currency_code: getString(rate, "currency_code"),
        amount: getString(rate, "amount"),
        total: getString(rate, "total"),
        days: getNumber(rate, "days"),
        shipment_creation_type: getString(rate, "shipment_creation_type"),
      };
    });
}

function extractTopLevelQuotationId(data: unknown): string | null {
  if (!isRecord(data)) return null;
  const id = data.id;
  return typeof id === "string" && id.trim() !== "" ? id.trim() : null;
}

function sanitizeQuotationState(
  quotationId: string,
  data: unknown,
  pollAttempts: number,
): JsonRecord {
  if (!isRecord(data)) {
    throw new Error("invalid_quotation_response");
  }

  const isCompleted = data.is_completed === true;
  return {
    ok: true,
    environment: "sandbox",
    quotation_created: true,
    quotation_id: getString(data, "id") ?? quotationId,
    is_completed: isCompleted,
    poll_attempts: pollAttempts,
    rates: isCompleted ? sanitizeRates(data.rates) : [],
  };
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: JSON_HEADERS });
  }

  if (request.method !== "POST") {
    return jsonResponse({ ok: false, error: "method_not_allowed" }, 405);
  }

  try {
    const rawBaseUrl = Deno.env.get("SKYDROPX_SANDBOX_BASE_URL")?.trim() ||
      "https://sb-pro.skydropx.com";
    const baseUrl = rawBaseUrl.replace(/\/+$/, "");

    let requestBody: unknown;
    try {
      requestBody = await request.json();
    } catch (_) {
      return jsonResponse(
        {
          ok: false,
          environment: "sandbox",
          quotation_created: false,
          error: "invalid_json_body",
        },
        400,
      );
    }

    let validated: ValidQuotationRequest;
    try {
      validated = validateBody(requestBody);
    } catch (error: unknown) {
      return jsonResponse(
        {
          ok: false,
          environment: "sandbox",
          quotation_created: false,
          error: "validation_error",
          message: error instanceof Error ? error.message : "invalid_request_body",
        },
        400,
      );
    }

    let accessToken: string;
    try {
      accessToken = await getSandboxAccessToken(baseUrl);
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : "oauth_error";
      const statusMatch = message.match(/^oauth_http_(\d{3})$/);
      const upstreamStatus = statusMatch ? Number(statusMatch[1]) : null;
      return jsonResponse(
        {
          ok: false,
          environment: "sandbox",
          quotation_created: false,
          error: message === "missing_oauth_configuration"
            ? "missing_configuration"
            : message === "invalid_json_response"
            ? "invalid_oauth_json_response"
            : "skydropx_oauth_error",
          status_code: upstreamStatus,
        },
        upstreamStatus ? safeStatus(upstreamStatus) : 502,
      );
    }

    let createResponse: Response;
    try {
      createResponse = await fetchWithTimeout(
        `${baseUrl}/api/v1/quotations`,
        {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${accessToken}`,
            "Content-Type": "application/json",
            "Accept": "application/json",
          },
          body: JSON.stringify({
            quotation: {
              address_from: validated.address_from,
              address_to: validated.address_to,
              parcels: validated.parcels,
            },
          }),
        },
        15000,
      );
    } catch (error: unknown) {
      const isAbort = error instanceof Error && error.name === "AbortError";
      return jsonResponse(
        {
          ok: false,
          environment: "sandbox",
          quotation_created: false,
          error: isAbort ? "create_request_timeout" : "create_network_error",
        },
        isAbort ? 504 : 502,
      );
    }

    let createData: unknown;
    try {
      createData = await parseJsonResponse(createResponse);
    } catch (_) {
      return jsonResponse(
        {
          ok: false,
          environment: "sandbox",
          quotation_created: false,
          status_code: createResponse.status,
          error: "invalid_create_json_response",
        },
        createResponse.ok ? 502 : safeStatus(createResponse.status),
      );
    }

    if (!createResponse.ok) {
      return jsonResponse(
        {
          ok: false,
          environment: "sandbox",
          quotation_created: false,
          status_code: createResponse.status,
          error: "skydropx_quotation_create_error",
        },
        safeStatus(createResponse.status),
      );
    }

    const quotationId = extractTopLevelQuotationId(createData);
    if (!quotationId) {
      return jsonResponse(
        {
          ok: false,
          environment: "sandbox",
          quotation_created: true,
          error: "missing_top_level_quotation_id",
        },
        502,
      );
    }

    let lastStatusCode: number | null = null;
    let lastData: unknown = createData;

    for (let attempt = 1; attempt <= 5; attempt++) {
      await sleep(2000);

      let getResponse: Response;
      try {
        getResponse = await fetchWithTimeout(
          `${baseUrl}/api/v1/quotations/${encodeURIComponent(quotationId)}`,
          {
            method: "GET",
            headers: {
              "Authorization": `Bearer ${accessToken}`,
              "Accept": "application/json",
            },
          },
          15000,
        );
      } catch (error: unknown) {
        const isAbort = error instanceof Error && error.name === "AbortError";
        return jsonResponse(
          {
            ok: false,
            environment: "sandbox",
            quotation_created: true,
            quotation_id: quotationId,
            error: isAbort ? "get_request_timeout" : "get_network_error",
            poll_attempts: attempt,
          },
          isAbort ? 504 : 502,
        );
      }

      lastStatusCode = getResponse.status;

      if (getResponse.status === 404) {
        return jsonResponse(
          {
            ok: false,
            environment: "sandbox",
            quotation_created: true,
            quotation_id: quotationId,
            get_status_code: 404,
            error: "quotation_not_found_after_creation",
          },
          404,
        );
      }

      let getData: unknown;
      try {
        getData = await parseJsonResponse(getResponse);
      } catch (_) {
        return jsonResponse(
          {
            ok: false,
            environment: "sandbox",
            quotation_created: true,
            quotation_id: quotationId,
            get_status_code: getResponse.status,
            error: "invalid_get_json_response",
            poll_attempts: attempt,
          },
          getResponse.ok ? 502 : safeStatus(getResponse.status),
        );
      }

      if (!getResponse.ok) {
        return jsonResponse(
          {
            ok: false,
            environment: "sandbox",
            quotation_created: true,
            quotation_id: quotationId,
            get_status_code: getResponse.status,
            error: "skydropx_quotation_get_error",
            poll_attempts: attempt,
          },
          safeStatus(getResponse.status),
        );
      }

      lastData = getData;
      if (isRecord(getData) && getData.is_completed === true) {
        return jsonResponse(sanitizeQuotationState(quotationId, getData, attempt));
      }
    }

    return jsonResponse({
      ...sanitizeQuotationState(quotationId, lastData, 5),
      get_status_code: lastStatusCode,
    });
  } catch (_error: unknown) {
    return jsonResponse(
      {
        ok: false,
        environment: "sandbox",
        quotation_created: false,
        error: "internal_server_error",
      },
      500,
    );
  }
});
