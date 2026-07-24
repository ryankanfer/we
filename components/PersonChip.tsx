"use client";

import { useSession } from "@/lib/session";
import type { PersonId } from "@/lib/types";

/** Identity is always color + text, never color alone. */
export default function PersonChip({ id, suffix }: { id: PersonId; suffix?: string }) {
  const member = useSession((s) => s.memberById(id));
  const dot = member?.hue === "sage" ? "bg-sage" : "bg-burgundy";
  return (
    <span className="inline-flex items-center gap-1.5 text-xs text-faint">
      <span className={`h-1.5 w-1.5 rounded-full ${dot}`} aria-hidden="true" />
      {member?.name ?? "Partner"}
      {suffix ? ` ${suffix}` : ""}
    </span>
  );
}
