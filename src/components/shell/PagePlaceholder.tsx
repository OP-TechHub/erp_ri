/** Temporary page body until the screen is built in its phase (docs/BUILD_PLAN.md). */
export function PagePlaceholder({ title, phase }: { title: string; phase: number }) {
  return (
    <div className="space-y-2">
      <h1 className="text-xl font-semibold">{title}</h1>
      <p className="text-sm text-muted-foreground">Coming in Phase {phase}.</p>
    </div>
  );
}
