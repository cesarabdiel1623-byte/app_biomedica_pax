import {
  calculateHmacSha512Hex,
  extractPayloadFields,
  handleRequest,
  parseSkydropxAuthorization,
  verifySkydropxSignature,
} from "./index.ts";

const panelPayload = {
  data: {
    data: {
      id: "package-panel-1",
      type: "packages",
      attributes: {
        status: "created",
        returned_status: null,
        returned: false,
        tracking_number: "TRACK123",
        tracking_url_provider: "https://carrier.example/track/TRACK123",
        label_url: "https://carrier.example/label.pdf",
        event_description: "Package created",
      },
      relationships: {
        shipment: {
          data: {
            id: "shipment-panel-1",
            type: "shipments",
          },
          links: {
            related: "https://api.example/shipments/shipment-panel-1",
          },
        },
      },
    },
  },
};

Deno.test("SkyDropX HMAC valido con prefijo HMAC es aceptado", async () => {
  const secret = "shared-secret";
  const rawBody = '{\n  "event": "unknown_test"\n}';
  const signature = await calculateHmacSha512Hex(secret, rawBody);

  const ok = await verifySkydropxSignature(
    rawBody,
    `HMAC ${signature}`,
    secret,
  );

  if (!ok) throw new Error("expected valid HMAC signature");
});

Deno.test("SkyDropX webhook acepta request firmado antes de parsear JSON", async () => {
  const secret = "shared-secret";
  const rawBody = '{\n  "event": "unknown_test"\n}';
  const signature = await calculateHmacSha512Hex(secret, rawBody);
  Deno.env.set("SKYDROPX_SANDBOX_WEBHOOK_SECRET", secret);

  const response = await handleRequest(
    new Request("https://example.test", {
      method: "POST",
      headers: { Authorization: `HMAC ${signature}` },
      body: rawBody,
    }),
  );

  if (response.status !== 200) {
    throw new Error(`expected 200, got ${response.status}`);
  }
});

Deno.test("SkyDropX HMAC con secret incorrecto devuelve falso", async () => {
  const rawBody = '{"event":"created"}';
  const signature = await calculateHmacSha512Hex("right-secret", rawBody);

  const ok = await verifySkydropxSignature(
    rawBody,
    `HMAC ${signature}`,
    "wrong-secret",
  );

  if (ok) throw new Error("expected invalid HMAC with wrong secret");
});

Deno.test("SkyDropX HMAC falla si el body raw se altera", async () => {
  const secret = "shared-secret";
  const rawBody = '{\n  "event": "created"\n}';
  const alteredBody = '{"event":"created"}';
  const signature = await calculateHmacSha512Hex(secret, rawBody);

  const ok = await verifySkydropxSignature(
    alteredBody,
    `HMAC ${signature}`,
    secret,
  );

  if (ok) throw new Error("expected invalid HMAC with altered body");
});

Deno.test("SkyDropX HMAC oficial exige firma lowercase", async () => {
  const secret = "shared-secret";
  const rawBody = '{"event":"created"}';
  const signature = await calculateHmacSha512Hex(secret, rawBody);

  if (parseSkydropxAuthorization(`HMAC ${signature}`) !== signature) {
    throw new Error("expected lowercase signature to parse");
  }

  if (parseSkydropxAuthorization(`HMAC ${signature.toUpperCase()}`) !== null) {
    throw new Error("expected uppercase signature to be rejected");
  }
});

Deno.test("SkyDropX HMAC usa raw body con espacios y saltos sin reconstruir", async () => {
  const secret = "shared-secret";
  const rawBody = '{\n  "event": "created",\n  "data": { "id": "ship-1" }\n}';
  const reconstructedBody = '{"event":"created","data":{"id":"ship-1"}}';
  const signature = await calculateHmacSha512Hex(secret, rawBody);

  const rawOk = await verifySkydropxSignature(
    rawBody,
    `HMAC ${signature}`,
    secret,
  );
  const reconstructedOk = await verifySkydropxSignature(
    reconstructedBody,
    `HMAC ${signature}`,
    secret,
  );

  if (!rawOk) throw new Error("expected raw body signature to be valid");
  if (reconstructedOk) {
    throw new Error("expected reconstructed body signature to be invalid");
  }
});

Deno.test("SkyDropX Authorization ausente devuelve 401", async () => {
  Deno.env.set("SKYDROPX_SANDBOX_WEBHOOK_SECRET", "shared-secret");

  const response = await handleRequest(
    new Request("https://example.test", {
      method: "POST",
      body: '{"event":"created"}',
    }),
  );

  if (response.status !== 401) {
    throw new Error(`expected 401, got ${response.status}`);
  }
});

Deno.test("SkyDropX Authorization sin prefijo HMAC devuelve 401", async () => {
  const secret = "shared-secret";
  const rawBody = '{"event":"created"}';
  const signature = await calculateHmacSha512Hex(secret, rawBody);
  Deno.env.set("SKYDROPX_SANDBOX_WEBHOOK_SECRET", secret);

  const response = await handleRequest(
    new Request("https://example.test", {
      method: "POST",
      headers: { Authorization: `Bearer ${signature}` },
      body: rawBody,
    }),
  );

  if (response.status !== 401) {
    throw new Error(`expected 401, got ${response.status}`);
  }
});

Deno.test("SkyDropX panel payload extrae status created desde data.data.attributes", () => {
  const fields = extractPayloadFields(panelPayload);
  if (fields.providerStatus !== "created") {
    throw new Error(`expected created, got ${fields.providerStatus}`);
  }
});

Deno.test("SkyDropX panel payload extrae shipment id desde relationship", () => {
  const fields = extractPayloadFields(panelPayload);
  if (fields.shipmentId !== "shipment-panel-1") {
    throw new Error(`expected shipment-panel-1, got ${fields.shipmentId}`);
  }
});

Deno.test("SkyDropX panel payload no confunde package id con shipment id", () => {
  const fields = extractPayloadFields(panelPayload);
  if (fields.packageId !== "package-panel-1") {
    throw new Error(`expected package-panel-1, got ${fields.packageId}`);
  }
  if (fields.shipmentId === fields.packageId) {
    throw new Error("package id was incorrectly used as shipment id");
  }
});

Deno.test("SkyDropX panel payload extrae tracking number", () => {
  const fields = extractPayloadFields(panelPayload);
  if (fields.trackingNumber !== "TRACK123") {
    throw new Error(`expected TRACK123, got ${fields.trackingNumber}`);
  }
});

Deno.test("SkyDropX panel payload extrae tracking_url_provider", () => {
  const fields = extractPayloadFields(panelPayload);
  if (fields.trackingUrl !== "https://carrier.example/track/TRACK123") {
    throw new Error(`unexpected tracking url ${fields.trackingUrl}`);
  }
});

Deno.test("SkyDropX panel payload extrae label_url", () => {
  const fields = extractPayloadFields(panelPayload);
  if (fields.labelUrl !== "https://carrier.example/label.pdf") {
    throw new Error(`unexpected label url ${fields.labelUrl}`);
  }
});

Deno.test("SkyDropX JSON:API directo payload.data tambien funciona", () => {
  const directPayload = { data: panelPayload.data.data };
  const fields = extractPayloadFields(directPayload);
  if (fields.providerStatus !== "created") {
    throw new Error(`expected created, got ${fields.providerStatus}`);
  }
  if (fields.shipmentId !== "shipment-panel-1") {
    throw new Error(`expected shipment-panel-1, got ${fields.shipmentId}`);
  }
});

Deno.test("SkyDropX payload sin status realmente devuelve missing_status", async () => {
  const secret = "shared-secret";
  const rawBody = JSON.stringify({
    data: {
      data: {
        id: "package-panel-1",
        type: "packages",
        attributes: {},
        relationships: panelPayload.data.data.relationships,
      },
    },
  });
  const signature = await calculateHmacSha512Hex(secret, rawBody);
  Deno.env.set("SKYDROPX_SANDBOX_WEBHOOK_SECRET", secret);

  const response = await handleRequest(
    new Request("https://example.test", {
      method: "POST",
      headers: { Authorization: `HMAC ${signature}` },
      body: rawBody,
    }),
  );
  const responseBody = await response.json();

  if (response.status !== 200 || responseBody.reason !== "missing_status") {
    throw new Error(`expected missing_status, got ${JSON.stringify(responseBody)}`);
  }
});

Deno.test("SkyDropX payload sin relationship shipment devuelve missing_shipment_id", async () => {
  const secret = "shared-secret";
  const rawBody = JSON.stringify({
    data: {
      data: {
        id: "package-panel-1",
        type: "packages",
        attributes: panelPayload.data.data.attributes,
      },
    },
  });
  const signature = await calculateHmacSha512Hex(secret, rawBody);
  Deno.env.set("SKYDROPX_SANDBOX_WEBHOOK_SECRET", secret);

  const response = await handleRequest(
    new Request("https://example.test", {
      method: "POST",
      headers: { Authorization: `HMAC ${signature}` },
      body: rawBody,
    }),
  );
  const responseBody = await response.json();

  if (
    response.status !== 200 ||
    responseBody.reason !== "missing_shipment_id"
  ) {
    throw new Error(`expected missing_shipment_id, got ${JSON.stringify(responseBody)}`);
  }
});
