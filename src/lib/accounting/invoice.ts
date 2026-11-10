import { round2 } from "./money";

/**
 * Sale invoice lines. Money as in the reference app (invRows):
 *   amount (net, excl. tax) = round2(qty × unit price × (1 − discount%)),  tax = round2(amount × tax%).
 * Price mode (added 2026-11-10):
 *   fixed – packs at the item master's pack price; any price typed on the line is ignored
 *   free  – quantity and price typed in, unit packs or kg (bulk orders); the per-kg price is only a suggestion
 */

export type PriceMode = "fixed" | "free";
export type SaleUnit = "pack" | "kg";

export type ItemPrices = { rate: number; kgRate: number | null }; // pack price, optional per-kg price

export type SaleLineInput = { mode: PriceMode; unit: SaleUnit; qty: number; unitPrice?: number | null };

export type SaleLine = { mode: PriceMode; unit: SaleUnit; qty: number; unitPrice: number; amount: number; tax: number };

/** Price shown when a line is started or its unit changes (the form's default). */
export function suggestedPrice(mode: PriceMode, unit: SaleUnit, item: ItemPrices): number | null {
  if (mode === "fixed" || unit === "pack") return item.rate;
  return item.kgRate;
}

/** The line as it will be saved, or an error message for the form. */
export function resolveSaleLine(
  input: SaleLineInput,
  item: ItemPrices,
  discountPct: number,
  taxPct: number,
): SaleLine | { error: string } {
  if (!(input.qty > 0)) return { error: "Quantity must be more than 0." };
  let unit = input.unit;
  let unitPrice: number;
  if (input.mode === "fixed") {
    if (unit !== "pack") return { error: "A fixed-price line is sold in packs." };
    unitPrice = item.rate;
    if (!(unitPrice > 0)) return { error: "This item has no pack price in the item master – use a free price." };
  } else {
    if (unit !== "pack" && unit !== "kg") unit = "kg";
    unitPrice = input.unitPrice ?? NaN;
    if (!(unitPrice > 0)) return { error: "Enter a unit price." };
  }
  const amount = round2(input.qty * unitPrice * (1 - discountPct / 100));
  return { mode: input.mode, unit, qty: input.qty, unitPrice, amount, tax: round2(amount * (taxPct / 100)) };
}
