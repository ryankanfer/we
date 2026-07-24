"use client";

import { useSession } from "@/lib/session";
import { projectFor } from "@/lib/consent";
import { TODAY } from "@/lib/demo";
import Icon from "@/components/Icon";
import InsightCard from "@/components/InsightCard";
import InterlockMark from "@/components/InterlockMark";
import InviteBanner from "@/components/InviteBanner";
import { Avatar, Card, Dot, SectionLabel } from "@/components/ui";

export default function Today() {
  const viewer = useSession((s) => s.viewer);
  const user = useSession((s) => s.user);
  const members = useSession((s) => s.members);
  const records = useSession((s) => s.records);
  const partner = members.find((m) => m.id !== viewer);

  const active = records
    .map((r) => ({ r, p: projectFor(r.state, viewer) }))
    .filter((x) => x.p && !x.p.dismissed && x.p.phase !== "resolved");

  return (
    <div>
      {/* Greeting */}
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="font-serif text-[2rem] leading-tight md:text-[2.4rem]">
            {TODAY.greeting}, {user?.name}.
          </h1>
          <p className="mt-1 text-sm text-faint">
            {partner ? `You and ${partner.name}, today.` : "Here’s what needs the two of you."}
          </p>
        </div>
        <span className="mt-1 grid h-9 w-9 place-items-center rounded-full border border-line text-faint">
          <Icon name="people" size={18} />
        </span>
      </div>

      <InviteBanner />

      <div className="mt-6 grid gap-6 lg:grid-cols-3">
        {/* Main column */}
        <div className="space-y-7 lg:col-span-2">
          {/* Today together */}
          <section>
            <SectionLabel>Today together</SectionLabel>
            <div className="grid gap-3 sm:grid-cols-2">
              <div className="rounded-2xl bg-ink px-5 py-5 text-cream">
                <p className="text-[11px] uppercase tracking-[0.14em] text-cream/60">At a glance</p>
                <ul className="mt-3 space-y-2.5 text-[15px]">
                  {TODAY.glance.map((g) => (
                    <li key={g.label} className="flex items-center gap-2.5">
                      <Icon name={g.icon as "calendar"} size={16} className="text-cream/70" />
                      {g.label}
                    </li>
                  ))}
                </ul>
              </div>
              <Card>
                <p className="text-[11px] uppercase tracking-[0.14em] text-faint">Energy check-in</p>
                <ul className="mt-3 space-y-3">
                  {members.map((m, i) => (
                    <li key={m.id} className="flex items-center justify-between text-[15px]">
                      <span className="flex items-center gap-2">
                        <Dot who={m.id} /> {m.id === viewer ? "You" : m.name}
                      </span>
                      <span className="text-faint">{TODAY.energy[i]?.state ?? "—"}</span>
                    </li>
                  ))}
                </ul>
              </Card>
            </div>
          </section>

          {/* Date night feature */}
          <section>
            <div className="flex items-center justify-between rounded-2xl bg-burgundy px-6 py-6 text-cream">
              <div>
                <p className="text-[11px] uppercase tracking-[0.14em] text-cream/60">{TODAY.dateNight.when}</p>
                <h2 className="mt-1 font-serif text-2xl">{TODAY.dateNight.title}</h2>
                <p className="mt-0.5 text-sm text-cream/75">{TODAY.dateNight.sub}</p>
              </div>
              <Icon name="utensils" size={30} className="text-cream/70" />
            </div>
          </section>

          {/* What needs us — the real consent core */}
          <section>
            <SectionLabel>What needs us</SectionLabel>
            {active.length === 0 ? (
              <Card className="flex flex-col items-center py-10 text-center">
                <InterlockMark size={44} overlap="interlocked" />
                <p className="mt-5 font-serif text-lg">All quiet.</p>
                <p className="mt-1 max-w-[26ch] text-sm text-faint">
                  WE stays still unless something is worth the two of you.
                </p>
              </Card>
            ) : (
              <div className="space-y-3">
                {active.map(({ r, p }) => (
                  <InsightCard key={r.insight.id} insight={r.insight} projection={p!} />
                ))}
              </div>
            )}
          </section>
        </div>

        {/* Side column */}
        <div className="space-y-7">
          <section>
            <SectionLabel>Needs attention</SectionLabel>
            <div className="space-y-3">
              <Card className="!bg-burgundy-soft">
                <div className="flex items-center gap-2">
                  {partner && <Avatar who={partner.id} size={24} />}
                  <p className="text-sm font-medium">{partner?.name ?? "Your partner"}</p>
                </div>
                <p className="mt-1.5 text-sm text-ink/75">Feeling stretched this week. A small check-in could land well.</p>
              </Card>
              <Card className="!bg-sage-soft">
                <p className="text-sm font-medium">You</p>
                <p className="mt-1.5 text-sm text-ink/75">Wanting more unhurried time together. Tomorrow is open.</p>
              </Card>
            </div>
          </section>

          <section>
            <SectionLabel>Tiny moment</SectionLabel>
            <Card className="flex items-center gap-3">
              <span className="grid h-10 w-10 place-items-center rounded-full bg-burgundy-soft text-burgundy">
                <Icon name="heart" size={18} />
              </span>
              <div className="min-w-0">
                <p className="text-[15px]">{TODAY.tinyMoment.title}</p>
                <p className="text-sm text-faint">
                  Send a small moment to {partner?.name ?? "your partner"}
                </p>
              </div>
              <Icon name="chevron" size={18} className="ml-auto text-faint" />
            </Card>
          </section>
        </div>
      </div>
    </div>
  );
}
