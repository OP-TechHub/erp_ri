import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { ORDER_SOURCES, orderSourceLabel, orderSourceSchema } from "./orderSource";

describe("order sources", () => {
  it("match the database enum", () => {
    const sql = readFileSync("supabase/migrations/0004_order_source.sql", "utf8");
    const m = /create type order_source as enum \(([^)]*)\)/.exec(sql);
    const dbValues = m![1].split(",").map((s) => s.trim().replace(/'/g, ""));
    expect(ORDER_SOURCES.map((s) => s.value)).toEqual(dbValues);
  });
  it("labels unknown / imported invoices as Not set", () => {
    expect(orderSourceLabel("whatsapp")).toBe("WhatsApp");
    expect(orderSourceLabel(null)).toBe("Not set");
  });
  it("rejects values outside the list", () => {
    expect(orderSourceSchema.safeParse("walk_in").success).toBe(true);
    expect(orderSourceSchema.safeParse("email").success).toBe(false);
  });
});
