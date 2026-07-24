"use client";

import { useState } from "react";
import { HOMEBOARD } from "@/lib/demo";
import { Avatar, Card, SectionLabel } from "@/components/ui";
import Icon from "@/components/Icon";

const TABS = ["Mental load", "Home", "Finances"];

export default function HomeBoard() {
  const [tab, setTab] = useState(0);
  return (
    <div>
      <div className="flex items-center justify-between">
        <h1 className="font-serif text-[2rem] leading-tight md:text-[2.4rem]">Home</h1>
        <span className="grid h-9 w-9 place-items-center rounded-full border border-line text-faint">
          <Icon name="people" size={18} />
        </span>
      </div>

      {/* Segmented tabs */}
      <div className="mt-5 inline-flex rounded-full border border-line bg-card p-1 text-sm">
        {TABS.map((t, i) => (
          <button
            key={t}
            onClick={() => setTab(i)}
            className={`rounded-full px-4 py-1.5 transition-colors ${
              tab === i ? "bg-ink text-cream" : "text-faint hover:text-ink"
            }`}
          >
            {t}
          </button>
        ))}
      </div>

      <div className="mt-7 grid gap-7 lg:grid-cols-3">
        <div className="space-y-7 lg:col-span-2">
          <section>
            <SectionLabel right={<span className="text-xs text-faint">View all</span>}>Up next</SectionLabel>
            <div className="divide-y divide-line overflow-hidden rounded-2xl border border-line bg-card">
              {HOMEBOARD.upNext.map((t) => (
                <div key={t.title} className="flex items-center gap-3 px-5 py-3.5">
                  <span className="h-4 w-4 rounded-full border border-faint/50" aria-hidden="true" />
                  <span className="text-[15px]">{t.title}</span>
                  <span className="ml-auto flex items-center gap-2 text-xs text-faint">
                    {t.who === "both" ? "Together" : "—"}
                    {t.who === "both" ? (
                      <span className="grid h-6 w-6 place-items-center rounded-full border border-line">
                        <Icon name="people" size={12} />
                      </span>
                    ) : (
                      <Avatar who={t.who} size={24} />
                    )}
                  </span>
                </div>
              ))}
            </div>
          </section>

          <section>
            <SectionLabel>Coming up</SectionLabel>
            <div className="space-y-3">
              {HOMEBOARD.comingUp.map((c) => (
                <Card key={c.title} className="flex items-center gap-3">
                  <span className="grid h-9 w-9 place-items-center rounded-full bg-cream text-faint">
                    <Icon name="receipt" size={16} />
                  </span>
                  <div>
                    <p className="text-[15px]">{c.title}</p>
                    <p className="text-sm text-faint">{c.sub}</p>
                  </div>
                </Card>
              ))}
            </div>
          </section>
        </div>

        <div>
          <SectionLabel>Going smoothly</SectionLabel>
          <div className="grid grid-cols-3 gap-3 lg:grid-cols-1">
            {HOMEBOARD.smoothly.map((s) => (
              <Card key={s.label} className="!bg-sage-soft flex flex-col items-center gap-1 py-4 text-center lg:flex-row lg:justify-start lg:text-left">
                <span className="grid h-9 w-9 place-items-center rounded-full bg-cream/70 text-sage">
                  <Icon name={s.icon as "basket"} size={16} />
                </span>
                <div>
                  <p className="text-[13px] font-medium">{s.label}</p>
                  <p className="text-xs text-faint">{s.sub}</p>
                </div>
              </Card>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
