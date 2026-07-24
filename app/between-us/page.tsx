"use client";

import { useWeStore } from "@/lib/store";
import { projectFor } from "@/lib/consent";
import InsightCard from "@/components/InsightCard";
import InterlockMark from "@/components/InterlockMark";

export default function BetweenUsPage() {
  const viewer = useWeStore((s) => s.viewer);
  const records = useWeStore((s) => s.records);

  const opened = records
    .map((r) => ({ r, p: projectFor(r.state, viewer) }))
    .filter((x) => x.p !== null && x.p!.visibility === "mutual");

  return (
    <div>
      <h1 className="font-serif text-[1.9rem] leading-tight">Between Us</h1>
      <p className="mt-2 text-sm text-faint">Only what you’ve both chosen to open, together.</p>

      {opened.length === 0 ? (
        <div className="mt-16 flex flex-col items-center text-center">
          <InterlockMark size={56} overlap="apart" />
          <p className="mt-6 font-serif text-xl">Nothing here yet.</p>
          <p className="mt-2 max-w-[28ch] text-sm leading-relaxed text-faint">
            Things arrive here only when both of you open them. Neither of you can put something
            here alone.
          </p>
        </div>
      ) : (
        <ul className="mt-6 space-y-3">
          {opened.map(({ r, p }) => (
            <li key={r.insight.id}>
              <InsightCard insight={r.insight} projection={p!} viewer={viewer} />
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
