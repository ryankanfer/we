"use client";

import { useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { useSession } from "@/lib/session";
import { projectFor } from "@/lib/consent";
import type { Domain, Insight } from "@/lib/types";
import InsightCard from "@/components/InsightCard";
import InterlockMark from "@/components/InterlockMark";
import InviteBanner from "@/components/InviteBanner";

/** A lens is a way of looking at the one shared life, not a separate room. */
type Lens = "today" | "life" | "us";

const LENSES: { id: Lens; label: string; note: string }[] = [
  { id: "today", label: "Today", note: "What needs the two of you now." },
  { id: "life", label: "Life", note: "The life you’re building and running together." },
  { id: "us", label: "Us", note: "The two of you — time, closeness, attention." },
];

function inLens(insight: Insight, lens: Lens): boolean {
  return lens === "today" ? insight.present : insight.domain === lens;
}

export default function Home() {
  const viewer = useSession((s) => s.viewer);
  const records = useSession((s) => s.records);
  const allReflections = useSession((s) => s.reflections);
  const [lens, setLens] = useState<Lens>("today");
  const reduceMotion = useReducedMotion();

  const projected = records
    .map((r) => ({ r, p: projectFor(r.state, viewer) }))
    .filter((x) => x.p !== null && !x.p!.dismissed && inLens(x.r.insight, lens));

  const active = projected.filter((x) => x.p!.phase !== "resolved");
  const settled = projected.filter((x) => x.p!.phase === "resolved");

  // Privacy as a property, not a place: the viewer's own reflections surface
  // inline, under the matching lens. Never shown in the time-based Today view.
  const reflections =
    lens === "today" ? [] : allReflections.filter((r) => (r.domain as Domain) === lens);

  const empty = active.length === 0 && reflections.length === 0 && settled.length === 0;
  const note = LENSES.find((l) => l.id === lens)!.note;

  return (
    <div>
      <h1 className="font-serif text-[1.9rem] leading-tight">What needs us?</h1>

      <InviteBanner />

      {/* Soft lenses — facets of one continuity, never separate destinations. */}
      <div className="mt-5" role="tablist" aria-label="Lenses">
        <div className="flex items-center gap-5">
          {LENSES.map((l) => {
            const on = l.id === lens;
            return (
              <button
                key={l.id}
                role="tab"
                aria-selected={on}
                onClick={() => setLens(l.id)}
                className={`relative pb-1 text-[15px] transition-colors ${
                  on ? "text-ink" : "text-faint hover:text-ink"
                }`}
              >
                {l.label}
                {on && (
                  <motion.span
                    layoutId="lens-underline"
                    className="absolute -bottom-px left-0 right-0 h-px bg-ink"
                  />
                )}
              </button>
            );
          })}
        </div>
        <p className="mt-2 text-xs text-faint">{note}</p>
      </div>

      <AnimatePresence mode="wait">
        <motion.div
          key={lens}
          initial={reduceMotion ? false : { opacity: 0, y: 6 }}
          animate={{ opacity: 1, y: 0 }}
          exit={reduceMotion ? undefined : { opacity: 0 }}
          transition={{ duration: 0.32, ease: [0.22, 1, 0.36, 1] }}
        >
          {empty ? (
            <div className="mt-16 flex flex-col items-center text-center">
              <InterlockMark size={52} overlap="interlocked" />
              <p className="mt-6 font-serif text-lg">All quiet here.</p>
              <p className="mt-2 max-w-[26ch] text-sm text-faint">
                WE stays still unless something is worth the two of you.
              </p>
            </div>
          ) : (
            <div className="mt-6 space-y-3">
              {active.map(({ r, p }) => (
                <InsightCard key={r.insight.id} insight={r.insight} projection={p!} />
              ))}

              {reflections.map((rfl) => (
                <ReflectionNote key={rfl.id} kind={rfl.kind} text={rfl.text} />
              ))}

              {settled.length > 0 && (
                <div className="pt-4">
                  <p className="text-[11px] uppercase tracking-[0.14em] text-faint">Settled together</p>
                  <div className="mt-3 space-y-3 opacity-70">
                    {settled.map(({ r, p }) => (
                      <InsightCard key={r.insight.id} insight={r.insight} projection={p!} />
                    ))}
                  </div>
                </div>
              )}
            </div>
          )}
        </motion.div>
      </AnimatePresence>
    </div>
  );
}

/** A private reflection, living inline in the shared stream — visible only to its owner. */
function ReflectionNote({ kind, text }: { kind: "reflection" | "suggestion"; text: string }) {
  return (
    <div className="rounded-2xl border border-dashed border-line bg-transparent px-5 py-4">
      <div className="flex items-center gap-2">
        <LockGlyph />
        <p className="text-[11px] uppercase tracking-[0.14em] text-faint">
          {kind === "suggestion" ? "A private thought from WE · only you" : "Yours · only you"}
        </p>
      </div>
      <p className="mt-2 font-serif text-[1.05rem] leading-relaxed text-ink/85">{text}</p>
    </div>
  );
}

function LockGlyph() {
  return (
    <svg width="11" height="11" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <rect x="5" y="11" width="14" height="9" rx="2" stroke="var(--color-faint)" strokeWidth="2" />
      <path d="M8 11V8a4 4 0 0 1 8 0v3" stroke="var(--color-faint)" strokeWidth="2" />
    </svg>
  );
}
