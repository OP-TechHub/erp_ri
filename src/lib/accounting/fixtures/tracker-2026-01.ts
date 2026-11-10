/** Figures from Round_Island_Monthly_Tracker.xlsx (illustrative January 2026 data), used to check the costing maths. */
export const PRICES: Record<string, number> = {
  "Barramundi Fillet": 1800, "Barramundi Offcut": 900, "Barramundi Belly Flap": 1100, "Mixed Vegetables": 250,
  "Spice Mix": 1200, "Marinate Mix": 900, "Pre-Dust Flour": 300, "Batter Mix": 350, Breadcrumbs: 280,
  "Frozen Pouch": 25, "Chilled Pouch": 22, Label: 3,
};

const fillet = (marinate: number, fish = 0.27): [string, number][] => [["Barramundi Fillet", fish], ["Marinate Mix", marinate], ["Spice Mix", 0.01], ["Frozen Pouch", 1], ["Label", 1]];
const soup = (pouch: string): [string, number][] => [["Barramundi Belly Flap", 0.15], ["Barramundi Offcut", 0.05], ["Mixed Vegetables", 0.08], ["Spice Mix", 0.01], [pouch, 1], ["Label", 1]];

/** product -> recipe, selling price, recipe cost per unit (tracker), units sold in 2026-01 */
export const PRODUCTS: { name: string; recipe: [string, number][]; price: number; recipeCost: number; units: number }[] = [
  { name: "Asian Tropical Marinated Fillet", recipe: fillet(0.02), price: 950, recipeCost: 544, units: 180 },
  { name: "Japanese Classic Marinated Fillet", recipe: fillet(0.02), price: 950, recipeCost: 544, units: 150 },
  { name: "Exotic Delight Marinated Fillet", recipe: fillet(0.02), price: 980, recipeCost: 544, units: 140 },
  { name: "Black Bean Glow Marinated Fillet", recipe: fillet(0.02), price: 980, recipeCost: 544, units: 120 },
  { name: "Barra Battered Fillets", recipe: [["Barramundi Fillet", 0.2], ["Pre-Dust Flour", 0.02], ["Batter Mix", 0.05], ["Frozen Pouch", 1], ["Label", 1]], price: 850, recipeCost: 411.5, units: 260 },
  { name: "Barra Spring Rolls", recipe: [["Barramundi Offcut", 0.15], ["Mixed Vegetables", 0.1], ["Spice Mix", 0.01], ["Pre-Dust Flour", 0.02], ["Frozen Pouch", 1], ["Label", 1]], price: 720, recipeCost: 206, units: 300 },
  { name: "Barra Kofta", recipe: [["Barramundi Offcut", 0.22], ["Mixed Vegetables", 0.05], ["Spice Mix", 0.02], ["Batter Mix", 0.02], ["Frozen Pouch", 1], ["Label", 1]], price: 780, recipeCost: 269.5, units: 210 },
  { name: "Barra Battered Goujons", recipe: [["Barramundi Fillet", 0.18], ["Pre-Dust Flour", 0.02], ["Batter Mix", 0.04], ["Breadcrumbs", 0.05], ["Frozen Pouch", 1], ["Label", 1]], price: 820, recipeCost: 386, units: 240 },
  { name: "Barra Burger Patties", recipe: [["Barramundi Offcut", 0.2], ["Barramundi Belly Flap", 0.05], ["Spice Mix", 0.02], ["Batter Mix", 0.03], ["Frozen Pouch", 1], ["Label", 1]], price: 790, recipeCost: 297.5, units: 220 },
  { name: "Barra BBQ-Marinated Butterfly Cuts", recipe: fillet(0.03, 0.32), price: 1150, recipeCost: 643, units: 90 },
  { name: "Barra Bits", recipe: [["Barramundi Offcut", 0.24], ["Pre-Dust Flour", 0.02], ["Batter Mix", 0.04], ["Frozen Pouch", 1], ["Label", 1]], price: 700, recipeCost: 264, units: 200 },
  { name: "Barra Battered Belly Strips", recipe: [["Barramundi Belly Flap", 0.22], ["Pre-Dust Flour", 0.02], ["Batter Mix", 0.04], ["Frozen Pouch", 1], ["Label", 1]], price: 760, recipeCost: 290, units: 170 },
  { name: "Barra Collagen Soup – Frozen", recipe: soup("Frozen Pouch"), price: 890, recipeCost: 270, units: 130 },
  { name: "Barra Collagen Soup – Chilled", recipe: soup("Chilled Pouch"), price: 950, recipeCost: 267, units: 110 },
];

/** Monthly Summary, 2026-01 */
export const SUMMARY = { revenue: 2132600, cogs: 928875, grossProfit: 1203725 };
