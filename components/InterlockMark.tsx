"use client";

/**
 * The consent motif: two circles — burgundy and sage — whose overlap
 * expresses the state between two people. Apart, approaching, interlocked.
 * This is WE's one recurring visual element; state never relies on it alone
 * (every use is paired with a text label).
 */
export default function InterlockMark({
  overlap = "apart",
  size = 40,
  breathing = false,
  className = "",
}: {
  overlap?: "apart" | "touching" | "interlocked";
  size?: number;
  breathing?: boolean;
  className?: string;
}) {
  const r = size * 0.28;
  const cy = size / 2;
  const gap = overlap === "apart" ? r * 2.6 : overlap === "touching" ? r * 2.0 : r * 1.15;
  const cx1 = size / 2 - gap / 2;
  const cx2 = size / 2 + gap / 2;

  return (
    <svg
      width={size}
      height={size}
      viewBox={`0 0 ${size} ${size}`}
      aria-hidden="true"
      className={`${breathing ? "breathe" : ""} ${className}`}
      style={{ overflow: "visible" }}
    >
      <circle
        cx={cx1}
        cy={cy}
        r={r}
        fill="none"
        stroke="var(--color-burgundy)"
        strokeWidth={size * 0.035}
        style={{ transition: "cx 0.9s cubic-bezier(0.22, 1, 0.36, 1)" }}
      />
      <circle
        cx={cx2}
        cy={cy}
        r={r}
        fill="none"
        stroke="var(--color-sage)"
        strokeWidth={size * 0.035}
        style={{ transition: "cx 0.9s cubic-bezier(0.22, 1, 0.36, 1)" }}
      />
    </svg>
  );
}
