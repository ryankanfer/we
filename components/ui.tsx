"use client";

import { useSession } from "@/lib/session";

export function SectionLabel({ children, right }: { children: React.ReactNode; right?: React.ReactNode }) {
  return (
    <div className="mb-3 flex items-center justify-between">
      <p className="text-[11px] uppercase tracking-[0.16em] text-faint">{children}</p>
      {right}
    </div>
  );
}

export function Card({
  children,
  className = "",
  as: Tag = "div",
}: {
  children: React.ReactNode;
  className?: string;
  as?: "div" | "section";
}) {
  return (
    <Tag className={`rounded-2xl border border-line bg-card px-5 py-5 ${className}`}>{children}</Tag>
  );
}

/** A person dot in their relational hue, always beside a label elsewhere. */
export function Dot({ who }: { who: string }) {
  const hue = useSession((s) => s.memberById(who)?.hue);
  return <span className={`inline-block h-2 w-2 rounded-full ${hue === "sage" ? "bg-sage" : "bg-burgundy"}`} aria-hidden="true" />;
}

export function Avatar({ who, size = 28 }: { who: string; size?: number }) {
  const member = useSession((s) => s.memberById(who));
  const soft = member?.hue === "sage" ? "bg-sage-soft text-sage" : "bg-burgundy-soft text-burgundy";
  return (
    <span
      className={`grid shrink-0 place-items-center rounded-full ${soft}`}
      style={{ width: size, height: size, fontSize: size * 0.4 }}
      aria-label={member?.name}
    >
      {(member?.name ?? "·").slice(0, 1)}
    </span>
  );
}
