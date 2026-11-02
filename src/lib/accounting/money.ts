/**
 * The one place money is rounded (CLAUDE.md rule 2): 2 dp, half-up (halves go away from zero).
 * The reference app uses Math.round(n*100)/100, which gets binary edge cases wrong
 * (1.005 -> 1.00); shifting through the decimal exponent avoids that.
 */
export function round2(n: number): number {
  if (!Number.isFinite(n)) return 0;
  const r = Number(Math.round(Number(Math.abs(n) + "e2")) + "e-2");
  return n < 0 ? -r : r;
}

/** The reference treats anything within half a cent of zero as zero. */
export function isZero(n: number): boolean {
  return Math.abs(n) <= 0.005;
}

/** Round each value first, then add – stored totals are never float sums of unrounded values. */
export function sumMoney(values: readonly number[]): number {
  return round2(values.reduce((s, v) => s + round2(v), 0));
}
