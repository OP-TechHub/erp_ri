import { describe, expect, it } from "vitest";
import { ingredientCost, lineCogs, monthlyAverageCosts, packsSold, recipeUnitCost, type RecipeLine } from "./costing";
import { round2, sumMoney } from "./money";
import { PRICES, PRODUCTS, SUMMARY } from "./fixtures/tracker-2026-01";

// one January purchase per ingredient at the tracker's unit cost
const table = monthlyAverageCosts(Object.entries(PRICES).map(([ingredientId, p]) => ({ ingredientId, date: "2026-01-05", qty: 10, amount: 10 * p })));
const recipe: RecipeLine[] = PRODUCTS.flatMap((p) => p.recipe.map(([ingredientId, qtyPerUnit]) => ({ productId: p.name, ingredientId, qtyPerUnit })));

describe("recipe cost per pack (tracker Product Master)", () => {
  it.each(PRODUCTS.map((p) => [p.name, p.recipeCost] as const))("%s = %d", (name, expected) => {
    expect(recipeUnitCost(recipe, name, "2026-01", table)).toEqual({ cost: expected, missing: [] });
  });
});

describe("January 2026 totals (tracker Monthly Summary)", () => {
  it("revenue, COGS and gross profit tie out", () => {
    const revenue = sumMoney(PRODUCTS.map((p) => p.units * p.price));
    const cogs = sumMoney(PRODUCTS.map((p) => lineCogs(p.units, recipeUnitCost(recipe, p.name, "2026-01", table).cost)));
    expect({ revenue, cogs, grossProfit: round2(revenue - cogs) }).toEqual(SUMMARY);
  });
});

describe("monthly weighted average", () => {
  const t = monthlyAverageCosts([
    { ingredientId: "fillet", date: "2026-02-03", qty: 10, amount: 17000 },
    { ingredientId: "fillet", date: "2026-02-20", qty: 30, amount: 57000 },
    { ingredientId: "fillet", date: "2026-04-02", qty: 10, amount: 20000 },
    { ingredientId: "fillet", date: "2026-04-09", qty: 5, amount: 10000, isReturn: true },
  ]);
  it("weights by quantity, not by number of purchases", () => {
    expect(ingredientCost(t, "fillet", "2026-02")).toBe(1850); // (17000 + 57000) / 40, not (1700 + 1900) / 2
  });
  it("uses the latest earlier month when nothing was bought", () => {
    expect(ingredientCost(t, "fillet", "2026-03")).toBe(1850);
  });
  it("takes purchase returns out", () => {
    expect(ingredientCost(t, "fillet", "2026-04")).toBe(2000); // (20000 - 10000) / (10 - 5)
  });
  it("has no cost before the first purchase, and reports it as missing", () => {
    expect(ingredientCost(t, "fillet", "2026-01")).toBeNull();
    const r = recipeUnitCost([{ productId: "x", ingredientId: "fillet", qtyPerUnit: 0.27 }, { productId: "x", ingredientId: "label", qtyPerUnit: 1 }], "x", "2026-02", t);
    expect(r).toEqual({ cost: 499.5, missing: ["label"] });
  });
});

describe("packs sold", () => {
  it("counts pack lines as entered and converts kg with the pack weight", () => {
    expect(packsSold("pack", 12, 300)).toBe(12);
    expect(packsSold("kg", 3, 300)).toBe(10); // bulk order: 3 kg of a 300g item
    expect(packsSold("kg", 2, null)).toBeNull(); // e.g. soup sold by kg with no pack weight set
  });
});
