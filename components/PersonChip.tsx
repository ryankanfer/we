"use client";

import { PEOPLE } from "@/lib/seed";
import type { PersonId } from "@/lib/types";

/** Identity is always color + text, never color alone. */
export default function PersonChip({ id, suffix }: { id: PersonId; suffix?: string }) {
  const p = PEOPLE[id];
  const dot = p.hue === "burgundy" ? "bg-burgundy" : "bg-sage";
  return (
    <span className="inline-flex items-center gap-1.5 text-xs text-faint">
      <span className={`h-1.5 w-1.5 rounded-full ${dot}`} aria-hidden="true" />
      {p.name}
      {suffix ? ` ${suffix}` : ""}
    </span>
  );
}
