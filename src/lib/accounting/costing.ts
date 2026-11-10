import { round2 } from "./money";

/**
 * Recipe costing (not in the reference app – added 2026-11 from Round_Island_Monthly_Tracker).
 * Ingredients have no price list: an ingredient's cost for a month is the weighted average of that
 * month's purchase lines (amount excl. tax ÷ qty). A month without purchases uses the most recent
 * earlier month that had some. A recipe gives the quantity of each ingredient in ONE pack.
 */

export type Month = string; // "yyyy-mm"

export type PurchaseLine = {
  ingredientId: string;
  date: string; // "yyyy-mm-dd"
  qty: number; // in the ingredient's unit
  amount: number; // excl. tax
  isReturn?: boolean; // purchase return: takes qty and amount out
};

export type RecipeLine = { productId: string; ingredientId: string; qtyPerUnit: number };

export type CostTable = Map<string, Map<Month, number>>; // ingredient -> month -> average unit cost

export const monthOf = (date: string): Month => date.slice(0, 7);

/** Weighted average unit cost per ingredient per month. */
export function monthlyAverageCosts(lines: readonly PurchaseLine[]): CostTable {
  const sums = new Map<string, Map<Month, { qty: number; amount: number }>>();
  for (const l of lines) {
    const sign = l.isReturn ? -1 : 1;
    const byMonth = sums.get(l.ingredientId) ?? new Map();
    const s = byMonth.get(monthOf(l.date)) ?? { qty: 0, amount: 0 };
    s.qty += sign * l.qty;
    s.amount += sign * l.amount;
    byMonth.set(monthOf(l.date), s);
    sums.set(l.ingredientId, byMonth);
  }
  const table: CostTable = new Map();
  for (const [ingredientId, byMonth] of sums) {
    const costs = new Map<Month, number>();
    for (const [m, s] of byMonth) if (s.qty > 0) costs.set(m, s.amount / s.qty);
    table.set(ingredientId, costs);
  }
  return table;
}

/** Cost of one unit of an ingredient in a month: that month's average, else the latest earlier month's; null if never bought. */
export function ingredientCost(table: CostTable, ingredientId: string, month: Month): number | null {
  const costs = table.get(ingredientId);
  if (!costs) return null;
  const exact = costs.get(month);
  if (exact !== undefined) return exact;
  let best: Month | null = null;
  for (const m of costs.keys()) if (m < month && (best === null || m > best)) best = m;
  return best === null ? null : costs.get(best)!;
}

export type UnitCost = { cost: number; missing: string[] };

/** Recipe cost of ONE pack: each ingredient line rounded to 2 dp, then summed. `missing` lists ingredients with no purchase yet. */
export function recipeUnitCost(recipe: readonly RecipeLine[], productId: string, month: Month, table: CostTable): UnitCost {
  let cost = 0;
  const missing: string[] = [];
  for (const r of recipe) {
    if (r.productId !== productId) continue;
    const c = ingredientCost(table, r.ingredientId, month);
    if (c === null) missing.push(r.ingredientId);
    else cost += round2(r.qtyPerUnit * c);
  }
  return { cost: round2(cost), missing };
}

/** Packs in a sale line: pack lines as entered; kg lines converted with the pack weight (null if the item has none). */
export function packsSold(unit: "pack" | "kg", qty: number, packWeightG: number | null): number | null {
  if (unit === "pack") return qty;
  return packWeightG && packWeightG > 0 ? (qty * 1000) / packWeightG : null;
}

/** Cost of goods for one sale line. */
export function lineCogs(packs: number, unitCost: number): number {
  return round2(packs * unitCost);
}
