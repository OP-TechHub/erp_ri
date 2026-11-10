import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { LINE_UNITS, formatQty } from "./units";

describe("line units", () => {
  it("match the database enum", () => {
    const sql = readFileSync("supabase/migrations/0005_items_costing.sql", "utf8");
    const m = /create type line_unit as enum \(([^)]*)\)/.exec(sql);
    expect(LINE_UNITS.map((u) => u.value)).toEqual(m![1].split(",").map((s) => s.trim().replace(/'/g, "")));
  });
  it("prints the QTY column with its unit", () => {
    expect(formatQty(10, "pack")).toBe("10 packs");
    expect(formatQty(1, "pack")).toBe("1 pack");
    expect(formatQty(3.5, "kg")).toBe("3.500 kg");
    expect(formatQty(2, null)).toBe("2");
  });
});
