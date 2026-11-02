import { describe, expect, it } from "vitest";
import { isZero, round2, sumMoney } from "./money";

describe("round2", () => {
  it("rounds half up at 2 dp", () => {
    expect(round2(1.005)).toBe(1.01);
    expect(round2(2.675)).toBe(2.68);
    expect(round2(1.004)).toBe(1);
    expect(round2(3682949.2103)).toBe(3682949.21);
  });
  it("rounds negative halves away from zero", () => {
    expect(round2(-1.005)).toBe(-1.01);
  });
  it("treats non-finite input as zero", () => {
    expect(round2(Number.NaN)).toBe(0);
  });
});

describe("isZero", () => {
  it("uses the half-cent tolerance from the reference", () => {
    expect(isZero(0.005)).toBe(true);
    expect(isZero(-0.004)).toBe(true);
    expect(isZero(0.006)).toBe(false);
  });
});

describe("sumMoney", () => {
  it("rounds each value before adding", () => {
    expect(sumMoney([0.105, 0.105, 0.105])).toBe(0.33);
    expect(sumMoney([0.1, 0.2])).toBe(0.3);
  });
});
