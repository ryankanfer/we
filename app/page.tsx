"use client";

import { useWeStore } from "@/lib/store";
import { projectFor } from "@/lib/consent";
import InsightCard from "@/components/InsightCard";
import InterlockMark from "@/components/InterlockMark";

export default function OursFeed() {
  const viewer = useWeStore((s) => s.viewer);
  const records = useWeStore((s) => s.records);
  const teachingSeen = useWeStore((s) => s.teachingSeen);
  const markTeachingSeen = useWeStore((s) => s.markTeachingSeen);

  const visible = records
    .map((r) => ({ r, p: projectFor(r.state, viewer) }))
    .filter((x) => x.p !== null && !x.p!.dismissed && x.p!.phase !== "resolved");

  const settled = records
    .map((r) => ({ r, p: projectFor(r.state, viewer) }))
    .filter((x) => x.p?.phase === "resolved");

  return (
    <div>
      <h1 className="font-serif text-[1.9rem] leading-tight">What needs us?</h1>

      {!teachingSeen && (
        <div className="mt-4 rounded-2xl bg-sage-soft px-5 py-4 text-sm leading-relaxed">
          <p>
            <span className="font-medium">Mine</span> is private.{" "}
            <span className="font-medium">Ours</span> is known.{" "}
            <span className="font-medium">Between Us</span> is what you’ve opened together.
          </p>
          <button
            onClick={markTeachingSeen}
            className="mt-2 text-xs text-faint underline underline-offset-2 hover:text-ink"
          >
            Got it
          </button>
        </div>
      )}

      {visible.length === 0 ? (
        <div className="mt-16 flex flex-col items-center text-center">
          <InterlockMark size={56} overlap="interlocked" />
          <p className="mt-6 font-serif text-xl">Nothing needs you right now.</p>
          <p className="mt-2 max-w-[26ch] text-sm text-faint">
            WE stays quiet unless something is worth your attention.
          </p>
        </div>
      ) : (
        <ul className="mt-5 space-y-3">
          {visible.map(({ r, p }) => (
            <li key={r.insight.id}>
              <InsightCard insight={r.insight} projection={p!} viewer={viewer} />
            </li>
          ))}
        </ul>
      )}

      {settled.length > 0 && (
        <div className="mt-8">
          <p className="text-[11px] uppercase tracking-[0.14em] text-faint">Recently settled</p>
          <ul className="mt-3 space-y-3 opacity-70">
            {settled.map(({ r, p }) => (
              <li key={r.insight.id}>
                <InsightCard insight={r.insight} projection={p!} viewer={viewer} />
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
