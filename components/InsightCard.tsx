"use client";

import Link from "next/link";
import type { Projection } from "@/lib/consent";
import { partnerOf } from "@/lib/consent";
import { PEOPLE } from "@/lib/seed";
import type { Insight, PersonId } from "@/lib/types";
import InterlockMark from "./InterlockMark";

const KIND_LABEL: Record<Insight["kind"], string> = {
  logistical: "Logistics",
  relational: "Time together",
  unresolved: "Still open",
};

export function statusLine(p: Projection, viewer: PersonId): string | null {
  const partner = PEOPLE[partnerOf(viewer)].name;
  switch (p.phase) {
    case "waiting":
      return `Waiting for ${partner} to open this with you`;
    case "invited":
      return `${PEOPLE[p.initiator!].name} brought this to you`;
    case "answering":
      return "Open between you — your answer is still yours";
    case "held":
      return `Your answer is in. Waiting for ${partner}’s`;
    case "revealed":
      return p.matched ? "You’re in the same place" : "Not in the same place yet";
    case "resolved":
      return p.resolution?.type === "leftOpen" ? "Left open, together" : "Settled together";
    default:
      return null;
  }
}

function markState(p: Projection): "apart" | "touching" | "interlocked" {
  if (p.phase === "revealed" || p.phase === "resolved") return "interlocked";
  if (p.phase === "waiting" || p.phase === "invited") return "touching";
  if (p.phase === "answering" || p.phase === "held") return "interlocked";
  return "apart";
}

export default function InsightCard({
  insight,
  projection,
  viewer,
}: {
  insight: Insight;
  projection: Projection;
  viewer: PersonId;
}) {
  const status = statusLine(projection, viewer);
  return (
    <Link
      href={`/insight/${insight.id}`}
      className="block rounded-2xl border border-line bg-card px-5 py-5 transition-colors hover:border-faint/60"
    >
      <div className="flex items-start justify-between gap-4">
        <p className="text-[11px] uppercase tracking-[0.14em] text-faint">
          {KIND_LABEL[insight.kind]}
        </p>
        <InterlockMark size={22} overlap={markState(projection)} breathing={projection.phase === "waiting"} />
      </div>
      <h2 className="mt-2 font-serif text-[1.35rem] leading-snug">{insight.title}</h2>
      {status && <p className="mt-3 text-sm text-faint">{status}</p>}
    </Link>
  );
}
