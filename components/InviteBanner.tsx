"use client";

import { useState } from "react";
import { useSession } from "@/lib/session";

/** Shown until the second person joins: the couple's code to share. */
export default function InviteBanner() {
  const couple = useSession((s) => s.couple);
  const members = useSession((s) => s.members);
  const [copied, setCopied] = useState(false);

  if (!couple || members.length >= 2) return null;

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(couple.joinCode);
      setCopied(true);
      setTimeout(() => setCopied(false), 1800);
    } catch {
      /* clipboard unavailable — the code is visible regardless */
    }
  };

  return (
    <div className="mt-4 rounded-2xl bg-sage-soft px-5 py-4">
      <p className="text-sm leading-relaxed">
        It’s just you here so far. Share this code with your partner so they can join your space.
      </p>
      <button
        onClick={copy}
        className="mt-3 inline-flex items-center gap-2 rounded-full bg-ink px-4 py-2 text-cream"
        aria-label={`Join code ${couple.joinCode}. Tap to copy.`}
      >
        <span className="font-serif text-lg tracking-[0.3em]">{couple.joinCode}</span>
        <span className="text-xs opacity-80">{copied ? "copied" : "tap to copy"}</span>
      </button>
    </div>
  );
}
