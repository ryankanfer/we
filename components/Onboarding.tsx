"use client";

import { useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { useWeStore } from "@/lib/store";
import { PEOPLE } from "@/lib/seed";
import type { PersonId } from "@/lib/types";
import InterlockMark from "./InterlockMark";

/**
 * First-run sequence: before WE shows anything, it states its contract.
 * Four beats — arrival, the three spaces, the promise, and identity.
 * One partner can complete this alone; nothing requires the other yet.
 */
export default function Onboarding() {
  const completeOnboarding = useWeStore((s) => s.completeOnboarding);
  const [step, setStep] = useState(0);
  const reduceMotion = useReducedMotion();

  const fade = reduceMotion
    ? {}
    : {
        initial: { opacity: 0, y: 10 },
        animate: { opacity: 1, y: 0 },
        exit: { opacity: 0 },
        transition: { duration: 0.5, ease: [0.22, 1, 0.36, 1] as const },
      };

  return (
    <div className="flex h-full flex-col">
      <AnimatePresence mode="wait">
        <motion.div key={step} {...fade} className="flex flex-1 flex-col">
          {step === 0 && <Arrival onNext={() => setStep(1)} />}
          {step === 1 && <HowItWorks onNext={() => setStep(2)} />}
          {step === 2 && <Promise_ onNext={() => setStep(3)} />}
          {step === 3 && <Identity onChoose={completeOnboarding} />}
        </motion.div>
      </AnimatePresence>

      <div className="flex items-center justify-center gap-2 pb-2 pt-6" aria-hidden="true">
        {[0, 1, 2, 3].map((i) => (
          <span
            key={i}
            className={`h-1 rounded-full transition-all duration-500 ${
              i === step ? "w-5 bg-ink/60" : "w-1 bg-ink/15"
            }`}
          />
        ))}
      </div>
    </div>
  );
}

function Next({ onClick, children }: { onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      className="w-full rounded-full bg-ink px-6 py-3.5 text-[15px] text-cream transition-opacity hover:opacity-90"
    >
      {children}
    </button>
  );
}

function Arrival({ onNext }: { onNext: () => void }) {
  return (
    <div className="flex flex-1 flex-col items-center justify-center text-center">
      <InterlockMark size={88} overlap="touching" breathing />
      <h1 className="mt-10 font-serif text-[2.1rem] tracking-[0.22em]">WE</h1>
      <p className="mt-4 max-w-[26ch] font-serif text-lg leading-relaxed text-ink/80">
        A quiet layer for the two of you.
      </p>
      <p className="mt-3 max-w-[30ch] text-sm leading-relaxed text-faint">
        WE notices what may need attention, and helps you meet it together — without turning your
        relationship into work.
      </p>
      <div className="mt-12 w-full">
        <Next onClick={onNext}>Come in</Next>
      </div>
    </div>
  );
}

function HowItWorks({ onNext }: { onNext: () => void }) {
  const facets: { name: string; line: string }[] = [
    { name: "Today", line: "What needs the two of you right now." },
    { name: "Life", line: "The life you’re building and running together." },
    { name: "Us", line: "The two of you — time, closeness, attention." },
  ];
  return (
    <div className="flex flex-1 flex-col justify-center">
      <div className="flex items-center gap-3">
        <InterlockMark size={34} overlap="interlocked" className="shrink-0" />
        <h2 className="font-serif text-[1.7rem] leading-snug">One shared place.</h2>
      </div>
      <p className="mt-4 text-sm leading-relaxed text-faint">
        Not two accounts and a shared folder — one continuity, for both of you. WE quietly keeps an
        eye on the life you share and surfaces only what’s worth your attention, seen through three
        lenses:
      </p>
      <div className="mt-7 space-y-5">
        {facets.map((f) => (
          <div key={f.name} className="border-l border-line pl-4">
            <p className="font-serif text-lg">{f.name}</p>
            <p className="mt-0.5 text-sm leading-relaxed text-faint">{f.line}</p>
          </div>
        ))}
      </div>
      <div className="mt-10">
        <Next onClick={onNext}>And one promise</Next>
      </div>
    </div>
  );
}

function Promise_({ onNext }: { onNext: () => void }) {
  const lines = [
    "Some things stay yours until you both choose to open them — together.",
    "“Not now” is always safe. No one is told, and no one keeps count.",
    "WE describes patterns. It never diagnoses people, and it never scores you.",
    "The better things are, the quieter WE becomes.",
  ];
  return (
    <div className="flex flex-1 flex-col justify-center">
      <h2 className="font-serif text-[1.7rem] leading-snug">The promise.</h2>
      <ul className="mt-8 space-y-5">
        {lines.map((l) => (
          <li key={l} className="flex items-start gap-3.5">
            <span className="mt-[0.65em] h-1 w-1 shrink-0 rounded-full bg-ink/40" aria-hidden="true" />
            <p className="font-serif text-[1.05rem] leading-relaxed text-ink/85">{l}</p>
          </li>
        ))}
      </ul>
      <div className="mt-12">
        <Next onClick={onNext}>That works for me</Next>
      </div>
    </div>
  );
}

function Identity({ onChoose }: { onChoose: (p: PersonId) => void }) {
  return (
    <div className="flex flex-1 flex-col justify-center">
      <h2 className="font-serif text-[1.7rem] leading-snug">And you are —</h2>
      <p className="mt-3 text-sm leading-relaxed text-faint">
        Just so WE knows who’s here. Your partner joins with their own sign-in, whenever they’re
        ready — nothing is waiting on them.
      </p>
      <div className="mt-8 space-y-3">
        {(Object.keys(PEOPLE) as PersonId[]).map((id) => {
          const p = PEOPLE[id];
          const soft = p.hue === "burgundy" ? "bg-burgundy-soft" : "bg-sage-soft";
          const dot = p.hue === "burgundy" ? "bg-burgundy" : "bg-sage";
          return (
            <button
              key={id}
              onClick={() => onChoose(id)}
              className={`flex w-full items-center gap-4 rounded-2xl ${soft} px-5 py-5 text-left transition-transform active:scale-[0.99]`}
            >
              <span className={`h-3 w-3 rounded-full ${dot}`} aria-hidden="true" />
              <span className="font-serif text-xl">I'm {p.name}</span>
            </button>
          );
        })}
      </div>
    </div>
  );
}
