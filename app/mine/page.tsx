"use client";

import { useWeStore } from "@/lib/store";
import { REFLECTIONS, PEOPLE } from "@/lib/seed";

export default function MinePage() {
  const viewer = useWeStore((s) => s.viewer);
  const mine = REFLECTIONS.filter((r) => r.owner === viewer);

  return (
    <div>
      <h1 className="font-serif text-[1.9rem] leading-tight">Mine</h1>
      <p className="mt-2 text-sm text-faint">
        Only you can see this. {PEOPLE[viewer].name === "Ry" ? "Dylan" : "Ry"} never will — not even
        a hint that it exists.
      </p>

      <div className="mt-6 space-y-3">
        {mine.map((r) => (
          <div key={r.id} className="rounded-2xl border border-line bg-card px-5 py-4">
            <p className="text-[11px] uppercase tracking-[0.14em] text-faint">
              {r.kind === "suggestion" ? "A private thought from WE" : "Your reflection"}
            </p>
            <p className="mt-2 font-serif text-[1.05rem] leading-relaxed">{r.text}</p>
          </div>
        ))}
      </div>
    </div>
  );
}
