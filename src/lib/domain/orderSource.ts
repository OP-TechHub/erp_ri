import { z } from "zod";

/** How a sale order came in. Must match the order_source enum in supabase/migrations/0004_order_source.sql. */
export const ORDER_SOURCES = [
  { value: "walk_in", label: "Walk-in" },
  { value: "call", label: "Call" },
  { value: "whatsapp", label: "WhatsApp" },
  { value: "website", label: "Website" },
  { value: "other", label: "Other" },
] as const;

export type OrderSource = (typeof ORDER_SOURCES)[number]["value"];

export const orderSourceSchema = z.enum(ORDER_SOURCES.map((s) => s.value) as [OrderSource, ...OrderSource[]]);

/** Label for lists and reports; invoices imported from the old app have no source. */
export function orderSourceLabel(value: string | null | undefined): string {
  return ORDER_SOURCES.find((s) => s.value === value)?.label ?? "Not set";
}
