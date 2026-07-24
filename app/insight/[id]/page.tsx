"use client";

import { use, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { useWeStore } from "@/lib/store";
import { partnerOf, projectFor, type Projection } from "@/lib/consent";
import { PEOPLE } from "@/lib/seed";
import type { Insight, PersonId } from "@/lib/types";
import InterlockMark from "@/components/InterlockMark";
import PersonChip from "@/components/PersonChip";

export default function InsightDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const viewer = useWeStore((s) => s.viewer);
  const record = useWeStore((s) => s.records.find((r) => r.insight.id === id));

  const projection = record ? projectFor(record.state, viewer) : null;

  // Invalid or private-to-the-other-partner deep link: recover gently.
  if (!record || !projection) {
    return (
      <div className="mt-16 flex flex-col items-center text-center">
        <InterlockMark size={48} overlap="apart" />
        <p className="mt-6 font-serif text-xl">This isn’t here anymore.</p>
        <Link href="/" className="mt-4 text-sm text-faint underline underline-offset-2 hover:text-ink">
          Back to Ours
        </Link>
      </div>
    );
  }

  return <Flow insight={record.insight} p={projection} viewer={viewer} />;
}

function Flow({ insight, p, viewer }: { insight: Insight; p: Projection; viewer: PersonId }) {
  const reduceMotion = useReducedMotion();
  const fade = reduceMotion
    ? {}
    : {
        initial: { opacity: 0, y: 8 },
        animate: { opacity: 1, y: 0 },
        exit: { opacity: 0 },
        transition: { duration: 0.45, ease: [0.22, 1, 0.36, 1] as const },
      };

  return (
    <div>
      <Link href="/" className="text-xs text-faint hover:text-ink">
        ← Ours
      </Link>

      <AnimatePresence mode="wait">
        <motion.div key={p.phase} {...fade} className="mt-4">
          {p.phase === "open" && <Open insight={insight} />}
          {p.phase === "waiting" && <Waiting insight={insight} p={p} viewer={viewer} />}
          {p.phase === "invited" && <Invited insight={insight} p={p} viewer={viewer} />}
          {(p.phase === "answering" || p.phase === "held") && (
            <Answering insight={insight} p={p} viewer={viewer} />
          )}
          {p.phase === "revealed" && <Revealed insight={insight} p={p} viewer={viewer} />}
          {p.phase === "resolved" && <Resolved insight={insight} p={p} viewer={viewer} />}
        </motion.div>
      </AnimatePresence>
    </div>
  );
}

/* ---------- shared pieces ---------- */

function Observation({ insight, muted = false }: { insight: Insight; muted?: boolean }) {
  return (
    <div className={muted ? "opacity-80" : ""}>
      <h1 className="font-serif text-[1.7rem] leading-snug">{insight.title}</h1>
      <p className="mt-3 text-[15px] leading-relaxed text-ink/80">{insight.body}</p>
    </div>
  );
}

function Evidence({ insight }: { insight: Insight }) {
  return (
    <div className="mt-5 rounded-xl bg-card px-4 py-3">
      <p className="text-[11px] uppercase tracking-[0.14em] text-faint">Why WE noticed this</p>
      <p className="mt-1.5 text-sm leading-relaxed">{insight.evidence}</p>
      <p className="mt-1 text-xs text-faint">{insight.source}</p>
    </div>
  );
}

function Primary({ onClick, children }: { onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      className="w-full rounded-full bg-ink px-6 py-3.5 text-[15px] text-cream transition-opacity hover:opacity-90"
    >
      {children}
    </button>
  );
}

function Quiet({ onClick, children }: { onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      className="w-full rounded-full px-6 py-3 text-sm text-faint transition-colors hover:text-ink"
    >
      {children}
    </button>
  );
}

/* ---------- phases ---------- */

function Open({ insight }: { insight: Insight }) {
  const request = useWeStore((s) => s.request);
  const dismiss = useWeStore((s) => s.dismiss);
  const router = useRouter();
  return (
    <div>
      <Observation insight={insight} />
      <Evidence insight={insight} />
      <div className="mt-8 space-y-1">
        <Primary onClick={() => request(insight.id)}>Bring this to us</Primary>
        <p className="pt-2 text-center text-xs text-faint">
          Your partner will see the topic and that it came from you — nothing more.
        </p>
        <Quiet onClick={() => router.push("/")}>Not now</Quiet>
        <Quiet
          onClick={() => {
            dismiss(insight.id);
            router.push("/");
          }}
        >
          Dismiss this suggestion — just for you
        </Quiet>
      </div>
    </div>
  );
}

function Waiting({ insight, p, viewer }: { insight: Insight; p: Projection; viewer: PersonId }) {
  const withdraw = useWeStore((s) => s.withdraw);
  const clock = useWeStore((s) => s.clock);
  const partner = PEOPLE[partnerOf(viewer)].name;
  const hoursWaiting = clock - (p.requestedAt ?? 0);
  const later = hoursWaiting >= 18;

  return (
    <div className="flex flex-col items-center pt-10 text-center">
      <InterlockMark size={72} overlap="touching" breathing />
      <p className="mt-8 font-serif text-[1.45rem] leading-snug">
        {later ? `Still with ${partner}.` : `Waiting for ${partner} to open this with you.`}
      </p>
      <p className="mt-3 max-w-[30ch] text-sm leading-relaxed text-faint">
        {later
          ? "This stays quietly open. WE won’t ask again, and no one is keeping count."
          : "They’ll come to it in their own time. WE won’t nudge."}
      </p>
      <p className="mt-6 max-w-[32ch] font-serif text-base text-ink/70">“{insight.title}”</p>
      <div className="mt-10 w-full">
        <Quiet onClick={() => withdraw(insight.id)}>Take it back — no record will remain</Quiet>
      </div>
    </div>
  );
}

function Invited({ insight, p, viewer }: { insight: Insight; p: Projection; viewer: PersonId }) {
  const accept = useWeStore((s) => s.accept);
  const decline = useWeStore((s) => s.decline);
  const router = useRouter();
  const from = PEOPLE[p.initiator!].name;

  return (
    <div>
      <div className="flex flex-col items-center pt-6 text-center">
        <InterlockMark size={56} overlap="touching" />
        <p className="mt-6 text-sm text-faint">
          <PersonChip id={p.initiator!} suffix="brought something to you" />
        </p>
        <h1 className="mt-3 max-w-[26ch] font-serif text-[1.6rem] leading-snug">{insight.title}</h1>
        <p className="mt-4 max-w-[32ch] text-sm leading-relaxed text-faint">
          Opening it means you’re ready to sit with this together. You’ll each answer privately
          first.
        </p>
      </div>
      <div className="mt-10 space-y-1">
        <Primary onClick={() => accept(insight.id)}>Open this together</Primary>
        <Quiet
          onClick={() => {
            decline(insight.id);
            router.push("/");
          }}
        >
          Not yet — {from} won’t be told
        </Quiet>
      </div>
    </div>
  );
}

function Answering({ insight, p, viewer }: { insight: Insight; p: Projection; viewer: PersonId }) {
  const submit = useWeStore((s) => s.submit);
  const [choice, setChoice] = useState<string | undefined>(p.myResponse.choice);
  const [note, setNote] = useState(p.myResponse.note ?? "");
  const partner = PEOPLE[partnerOf(viewer)].name;
  const held = p.phase === "held";

  if (held) {
    return (
      <div className="flex flex-col items-center pt-10 text-center">
        <InterlockMark size={72} overlap="interlocked" breathing />
        <p className="mt-8 font-serif text-[1.45rem] leading-snug">Your answer is in.</p>
        <p className="mt-3 max-w-[30ch] text-sm leading-relaxed text-faint">
          It stays yours until {partner} has answered too. Then you’ll see both, together.
        </p>
        <p className="mt-6 max-w-[32ch] font-serif text-base text-ink/70">“{insight.title}”</p>
      </div>
    );
  }

  return (
    <div>
      <Observation insight={insight} muted />
      <fieldset className="mt-6">
        <legend className="text-[11px] uppercase tracking-[0.14em] text-faint">
          Your answer — private until you’ve both answered
        </legend>
        <div className="mt-3 space-y-2">
          {insight.options.map((opt) => (
            <label
              key={opt}
              className={`flex cursor-pointer items-center gap-3 rounded-xl border px-4 py-3.5 text-[15px] transition-colors ${
                choice === opt ? "border-ink bg-card" : "border-line bg-card/50 hover:border-faint/60"
              }`}
            >
              <input
                type="radio"
                name="choice"
                value={opt}
                checked={choice === opt}
                onChange={() => setChoice(opt)}
                className="accent-[var(--color-ink)]"
              />
              {opt}
            </label>
          ))}
        </div>
      </fieldset>
      <label className="mt-4 block">
        <span className="text-[11px] uppercase tracking-[0.14em] text-faint">
          A private note, if you want one
        </span>
        <textarea
          value={note}
          onChange={(e) => setNote(e.target.value)}
          rows={3}
          placeholder="Only revealed alongside theirs."
          className="mt-2 w-full resize-none rounded-xl border border-line bg-card px-4 py-3 text-[15px] leading-relaxed placeholder:text-faint/70 focus:border-ink focus:outline-none"
        />
      </label>
      <div className="mt-6">
        <Primary
          onClick={() => {
            if (choice) submit(insight.id, choice, note.trim() || undefined);
          }}
        >
          {choice ? "Share when you’re both ready" : "Choose an answer first"}
        </Primary>
      </div>
    </div>
  );
}

function AnswerCard({ person, choice, note }: { person: PersonId; choice?: string; note?: string }) {
  const hue = PEOPLE[person].hue === "burgundy" ? "bg-burgundy-soft" : "bg-sage-soft";
  return (
    <div className={`rounded-2xl ${hue} px-5 py-4`}>
      <PersonChip id={person} suffix="chose" />
      <p className="mt-1.5 font-serif text-lg">{choice}</p>
      {note && <p className="mt-2 text-sm leading-relaxed text-ink/75">“{note}”</p>}
    </div>
  );
}

function Revealed({ insight, p, viewer }: { insight: Insight; p: Projection; viewer: PersonId }) {
  const settle = useWeStore((s) => s.settle);
  const [showDetail, setShowDetail] = useState(false);
  const partner = partnerOf(viewer);
  const matched = p.matched === true;

  return (
    <div>
      <div className="flex flex-col items-center pt-4 text-center">
        <InterlockMark size={56} overlap={matched ? "interlocked" : "touching"} />
        <h1 className="mt-5 max-w-[24ch] font-serif text-[1.6rem] leading-snug">
          {matched ? "You’re in the same place." : "You’re not in the same place yet."}
        </h1>
        {!matched && (
          <p className="mt-2 text-sm text-faint">Nothing has been decided.</p>
        )}
        <p className="mt-4 max-w-[32ch] font-serif text-base text-ink/70">“{insight.title}”</p>
      </div>

      {(matched || showDetail) && (
        <div className="mt-6 space-y-3">
          <AnswerCard person={viewer} choice={p.myResponse.choice} note={p.myResponse.note} />
          <AnswerCard person={partner} choice={p.partnerResponse?.choice} note={p.partnerResponse?.note} />
        </div>
      )}

      <div className="mt-8 space-y-1">
        {matched ? (
          <Primary
            onClick={() =>
              settle(
                insight.id,
                p.myResponse.choice === "Let this go together" ? "released" : "settled",
                p.myResponse.choice
              )
            }
          >
            {p.myResponse.choice === "Let this go together"
              ? "Let it go, together"
              : "Mark it settled"}
          </Primary>
        ) : (
          <>
            {!showDetail && (
              <Primary onClick={() => setShowDetail(true)}>See what matters to each of you</Primary>
            )}
            <Quiet onClick={() => settle(insight.id, "leftOpen")}>
              Leave this open — it can wait
            </Quiet>
          </>
        )}
      </div>
    </div>
  );
}

function Resolved({ insight, p, viewer }: { insight: Insight; p: Projection; viewer: PersonId }) {
  const partner = partnerOf(viewer);
  const label =
    p.resolution?.type === "released"
      ? "Let go, together."
      : p.resolution?.type === "leftOpen"
        ? "Left open, together."
        : "Settled, together.";
  return (
    <div>
      <div className="flex flex-col items-center pt-8 text-center">
        <InterlockMark size={56} overlap="interlocked" />
        <p className="mt-6 font-serif text-[1.5rem]">{label}</p>
        <p className="mt-3 max-w-[32ch] font-serif text-base text-ink/70">“{insight.title}”</p>
        {p.resolution?.choice && p.resolution.type === "settled" && (
          <p className="mt-2 text-sm text-faint">You chose: {p.resolution.choice}</p>
        )}
      </div>
      <div className="mt-8 space-y-3 opacity-80">
        <AnswerCard person={viewer} choice={p.myResponse.choice} note={p.myResponse.note} />
        <AnswerCard person={partner} choice={p.partnerResponse?.choice} note={p.partnerResponse?.note} />
      </div>
    </div>
  );
}
