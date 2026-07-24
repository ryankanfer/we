"use client";

import { WEEK } from "@/lib/demo";
import { Card, Dot } from "@/components/ui";
import Icon from "@/components/Icon";

export default function Plan() {
  return (
    <div>
      <div className="flex items-center justify-between">
        <h1 className="font-serif text-[2rem] leading-tight md:text-[2.4rem]">This week</h1>
        <span className="grid h-9 w-9 place-items-center rounded-full border border-line text-faint">
          <Icon name="calendar" size={18} />
        </span>
      </div>

      {/* Week strip */}
      <div className="mt-6 grid grid-cols-7 gap-1 text-center">
        {WEEK.days.map((d) => {
          const on = d.n === WEEK.today;
          return (
            <div key={d.n} className="flex flex-col items-center gap-2 py-1">
              <span className="text-[11px] uppercase tracking-wider text-faint">{d.d}</span>
              <span
                className={`grid h-9 w-9 place-items-center rounded-full text-sm ${
                  on ? "bg-ink text-cream" : "text-ink"
                }`}
              >
                {d.n}
              </span>
            </div>
          );
        })}
      </div>

      {/* Day schedule */}
      <div className="mt-6 space-y-2.5">
        {WEEK.events.map((e) => (
          <div key={e.time} className="flex gap-4">
            <span className="w-14 shrink-0 pt-3 text-right text-xs text-faint">{e.time}</span>
            <div
              className={`flex flex-1 items-center gap-3 rounded-xl px-4 py-3 ${
                e.accent ? "bg-burgundy text-cream" : "border border-line bg-card"
              }`}
            >
              {e.who !== "both" && !e.accent && <Dot who={e.who} />}
              <span className={`text-[15px] ${e.accent ? "" : ""}`}>{e.title}</span>
              {e.who === "both" && !e.accent && (
                <span className="ml-auto text-[11px] uppercase tracking-wider text-faint">Together</span>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
