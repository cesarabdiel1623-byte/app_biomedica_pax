import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

export type JsonRecord = Record<string, unknown>;
export type SupabaseAdminClient = SupabaseClient;
export type SkydropxEnvironment = "sandbox" | "production";

export const REQUIRED_ORIGIN_FIELDS = [
  "country_code",
  "postal_code",
  "area_level1",
  "area_level2",
  "area_level3",
  "name",
  "street1",
  "company",
  "phone",
  "email",
  "reference",
] as const;

export const SKYDROPX_SANDBOX_TEST_ORIGIN: JsonRecord = {
  country_code: "MX",
  postal_code: "97392",
  area_level1: "Yucatán",
  area_level2: "Umán",
  area_level3: "Piedra de Agua",
  name: "Go Medical Almacén Sandbox",
  street1: "Calle 45A x 36 y 36c, No. 927H",
  company: "Go Medical",
  phone: "9995266748",
  email: "contacto@gomedical.mx",
  reference: "Almacén Sandbox Go Medical",
};

function getString(source: JsonRecord | null | undefined, key: string): string | null {
  if (!source) return null;
  const value = source[key];
  if (typeof value === "string" && value.trim() !== "") return value.trim();
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  return null;
}

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function resolveSkydropxEnvironment(raw?: string | null): SkydropxEnvironment {
  const envVal = raw !== undefined ? raw : Deno.env.get("SKYDROPX_ENV");
  if (envVal === undefined || envVal === null || envVal.trim() === "") {
    throw new Error("skydropx_environment_not_configured");
  }
  const normalized = envVal.trim().toLowerCase();
  if (normalized === "sandbox") return "sandbox";
  if (normalized === "production") return "production";
  throw new Error("invalid_skydropx_environment");
}

export function validateOriginAddress(origin: JsonRecord, errorName: string): JsonRecord {
  const validOrigin: JsonRecord = {};
  for (const field of REQUIRED_ORIGIN_FIELDS) {
    const value = getString(origin, field);
    if (!value) throw new Error(errorName);
    validOrigin[field] = field === "country_code" ? value.toUpperCase() : value;
  }
  if (validOrigin.country_code !== "MX") throw new Error(errorName);
  return validOrigin;
}

export function mapWarehouseToOrigin(warehouse: JsonRecord): JsonRecord {
  return validateOriginAddress({
    country_code: getString(warehouse, "country_code"),
    postal_code: getString(warehouse, "postal_code"),
    area_level1: getString(warehouse, "state"),
    area_level2: getString(warehouse, "city"),
    area_level3: getString(warehouse, "neighborhood"),
    name: getString(warehouse, "contact_name"),
    street1: getString(warehouse, "street1"),
    company: getString(warehouse, "company"),
    phone: getString(warehouse, "phone"),
    email: getString(warehouse, "email"),
    reference: getString(warehouse, "reference"),
  }, "invalid_shipping_origin");
}

export function loadSandboxOrigin(): JsonRecord {
  const rawOrigin = Deno.env.get("SKYDROPX_SANDBOX_ORIGIN_JSON")?.trim();
  if (!rawOrigin) {
    return validateOriginAddress(SKYDROPX_SANDBOX_TEST_ORIGIN, "skydropx_origin_not_configured");
  }

  try {
    const parsed = JSON.parse(rawOrigin);
    if (!isRecord(parsed)) throw new Error("skydropx_origin_not_configured");
    return validateOriginAddress(parsed, "skydropx_origin_not_configured");
  } catch (_) {
    return validateOriginAddress(SKYDROPX_SANDBOX_TEST_ORIGIN, "skydropx_origin_not_configured");
  }
}

export async function resolveShippingOrigin(
  adminClient: SupabaseAdminClient,
  environment?: string | null,
): Promise<{ origin: JsonRecord; source: "warehouse" | "sandbox_preset" | "sandbox_secret" }> {
  const env = resolveSkydropxEnvironment(environment);

  if (env === "sandbox") {
    const origin = loadSandboxOrigin();
    const source = Deno.env.get("SKYDROPX_SANDBOX_ORIGIN_JSON")?.trim()
      ? "sandbox_secret"
      : "sandbox_preset";
    return { origin, source };
  }

  if (env === "production") {
    const { data, error } = await adminClient
      .from("warehouses")
      .select(
        "name, company, contact_name, phone, email, street1, postal_code, country_code, state, city, neighborhood, reference",
      )
      .eq("is_active", true)
      .eq("is_shipping_origin", true);

    if (error) throw new Error("invalid_shipping_origin");
    const warehouses = Array.isArray(data) ? data.filter(isRecord) : [];

    if (warehouses.length === 0) {
      throw new Error("shipping_origin_not_configured");
    }

    if (warehouses.length > 1) {
      throw new Error("multiple_shipping_origins");
    }

    return { origin: mapWarehouseToOrigin(warehouses[0]), source: "warehouse" };
  }

  throw new Error("invalid_skydropx_environment");
}
