import { describe, expect, it } from "vitest";
import { resolveSaleLine, suggestedPrice } from "./invoice";

const springRolls = { rate: 720, kgRate: null }; // Product Master: Barra Spring Rolls 300g, 720 per pack

describe("fixed price lines", () => {
  it("use the item master's pack price, whatever is typed", () => {
    expect(resolveSaleLine({ mode: "fixed", unit: "pack", qty: 10, unitPrice: 500 }, springRolls, 0, 0)).toEqual({
      mode: "fixed", unit: "pack", qty: 10, unitPrice: 720, amount: 7200, tax: 0,
    });
  });
  it("are always in packs", () => {
    expect(resolveSaleLine({ mode: "fixed", unit: "kg", qty: 3 }, springRolls, 0, 0)).toEqual({ error: "A fixed-price line is sold in packs." });
  });
  it("need a pack price in the item master", () => {
    expect(resolveSaleLine({ mode: "fixed", unit: "pack", qty: 1 }, { rate: 0, kgRate: null }, 0, 0)).toHaveProperty("error");
  });
});

describe("free price lines", () => {
  it("take the typed quantity and price – a bulk order in kg", () => {
    expect(resolveSaleLine({ mode: "free", unit: "kg", qty: 12.5, unitPrice: 2100 }, springRolls, 0, 0)).toMatchObject({ unit: "kg", unitPrice: 2100, amount: 26250 });
  });
  it("can also be packs at a special price", () => {
    expect(resolveSaleLine({ mode: "free", unit: "pack", qty: 50, unitPrice: 650 }, springRolls, 0, 0)).toMatchObject({ unit: "pack", amount: 32500 });
  });
  it("need a price", () => {
    expect(resolveSaleLine({ mode: "free", unit: "kg", qty: 2 }, springRolls, 0, 0)).toEqual({ error: "Enter a unit price." });
  });
});

describe("money (reference invRows)", () => {
  it("applies the discount to the line, then VAT & SSCL on the net, rounding each", () => {
    // 3 × 1175 = 3525; less 7.5 % = 3260.625 -> 3260.63; tax 18 % = 586.9134 -> 586.91
    expect(resolveSaleLine({ mode: "free", unit: "pack", qty: 3, unitPrice: 1175 }, springRolls, 7.5, 18)).toMatchObject({ amount: 3260.63, tax: 586.91 });
  });
  it("rejects zero or negative quantities", () => {
    expect(resolveSaleLine({ mode: "fixed", unit: "pack", qty: 0 }, springRolls, 0, 0)).toEqual({ error: "Quantity must be more than 0." });
  });
});

describe("suggested price", () => {
  it("is the pack price for packs and the per-kg price (if any) for kg", () => {
    expect(suggestedPrice("fixed", "pack", springRolls)).toBe(720);
    expect(suggestedPrice("free", "kg", { rate: 720, kgRate: 2200 })).toBe(2200);
    expect(suggestedPrice("free", "kg", springRolls)).toBeNull();
  });
});

describe("price modes", () => {
  it("match the database enum", async () => {
    const { readFileSync } = await import("node:fs");
    const sql = readFileSync("supabase/migrations/0006_line_price_mode.sql", "utf8");
    expect(/create type price_mode as enum \(([^)]*)\)/.exec(sql)![1]).toBe("'fixed', 'free'");
  });
});
