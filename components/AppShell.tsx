"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useWeStore } from "@/lib/store";
import { PEOPLE } from "@/lib/seed";
import type { PersonId } from "@/lib/types";
import InterlockMark from "./InterlockMark";

const TABS = [
  { href: "/mine", label: "Mine" },
  { href: "/", label: "Ours" },
  { href: "/between-us", label: "Between Us" },
];

export default function AppShell({ children }: { children: React.ReactNode }) {
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const pathname = usePathname();
  const viewer = useWeStore((s) => s.viewer);
  const announcement = useWeStore((s) => s.announcement);

  return (
    <div className="flex min-h-dvh flex-col items-center gap-4 px-3 py-4 sm:py-8">
      {/* The phone: WE itself. */}
      <div className="flex w-full max-w-[430px] flex-1 flex-col overflow-hidden rounded-[2rem] border border-line bg-cream shadow-[0_1px_2px_rgba(39,33,26,0.06)]">
        <header className="flex items-center justify-between px-6 pb-2 pt-6">
          <Link href="/" className="flex items-center gap-2.5" aria-label="WE home">
            <InterlockMark size={26} overlap="interlocked" />
            <span className="font-serif text-lg tracking-[0.18em]">WE</span>
          </Link>
          {mounted && (
            <span className="text-xs text-faint" aria-label={`Viewing as ${PEOPLE[viewer].name}`}>
              {PEOPLE[viewer].name}
            </span>
          )}
        </header>

        <main className="flex-1 overflow-y-auto px-6 pb-6 pt-2">
          {mounted ? children : <div aria-hidden="true" />}
        </main>

        <nav aria-label="Spaces" className="border-t border-line px-6 py-3">
          <ul className="flex items-center justify-between">
            {TABS.map((t) => {
              const active = pathname === t.href;
              return (
                <li key={t.href}>
                  <Link
                    href={t.href}
                    aria-current={active ? "page" : undefined}
                    className={`rounded-full px-4 py-2 text-sm transition-colors ${
                      active ? "bg-ink text-cream" : "text-faint hover:text-ink"
                    }`}
                  >
                    {t.label}
                  </Link>
                </li>
              );
            })}
          </ul>
        </nav>
      </div>

      {/* Screen-reader announcements for consent transitions. */}
      <div aria-live="polite" className="sr-only">
        {mounted ? announcement : ""}
      </div>

      {mounted && <DemoController viewer={viewer} />}
    </div>
  );
}

/**
 * Explicitly OUTSIDE the phone frame: this is the research harness, not WE.
 * It lets one tester experience both partners and the passage of time.
 * It never exposes the other partner's private content — switching identity
 * re-projects the entire app through the consent layer.
 */
function DemoController({ viewer }: { viewer: PersonId }) {
  const setViewer = useWeStore((s) => s.setViewer);
  const advanceClock = useWeStore((s) => s.advanceClock);
  const reset = useWeStore((s) => s.reset);
  const clock = useWeStore((s) => s.clock);

  return (
    <aside
      aria-label="Demo controls"
      className="w-full max-w-[430px] rounded-xl border border-dashed border-faint/50 bg-outer px-4 py-3 text-xs text-faint"
    >
      <p className="mb-2 font-medium uppercase tracking-wider text-[10px]">
        Demo controls — not part of WE
      </p>
      <div className="flex flex-wrap items-center gap-2">
        <span>Experience as</span>
        {(Object.keys(PEOPLE) as PersonId[]).map((id) => (
          <button
            key={id}
            onClick={() => setViewer(id)}
            aria-pressed={viewer === id}
            className={`rounded-full border px-3 py-1 transition-colors ${
              viewer === id
                ? "border-ink bg-ink text-cream"
                : "border-faint/40 hover:border-ink"
            }`}
          >
            {PEOPLE[id].name}
          </button>
        ))}
        <span className="mx-1 h-4 w-px bg-faint/30" aria-hidden="true" />
        <button
          onClick={() => advanceClock(18)}
          className="rounded-full border border-faint/40 px-3 py-1 hover:border-ink"
        >
          Advance 18 hours
        </button>
        <span>{clock > 0 ? `+${clock}h` : "now"}</span>
        <span className="mx-1 h-4 w-px bg-faint/30" aria-hidden="true" />
        <button
          onClick={() => reset()}
          className="rounded-full border border-faint/40 px-3 py-1 hover:border-ink"
        >
          Reset demo
        </button>
      </div>
    </aside>
  );
}
