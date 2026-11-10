/** Unit of an invoice / bill line. Must match the line_unit enum in supabase/migrations/0005_items_costing.sql. */
export const LINE_UNITS = [
  { value: "pack", label: "packs", short: "pk" },
  { value: "kg", label: "kg", short: "kg" },
  { value: "unit", label: "units", short: "u" },
  { value: "l", label: "l", short: "l" },
] as const;

export type LineUnit = (typeof LINE_UNITS)[number]["value"];

/** Units a sale line can use: retail packs, or kg for bulk orders. */
export const SALE_UNITS: readonly LineUnit[] = ["pack", "kg"];

/** "10 packs", "3.500 kg" – the invoice QTY column. */
export function formatQty(qty: number, unit: LineUnit | null): string {
  if (unit === "kg" || unit === "l") return `${qty.toFixed(3)} ${unit}`;
  const n = Number.isInteger(qty) ? String(qty) : qty.toFixed(3);
  if (unit === "pack") return `${n} ${qty === 1 ? "pack" : "packs"}`;
  if (unit === "unit") return `${n} ${qty === 1 ? "unit" : "units"}`;
  return n; // lines imported from the old app have no unit
}
