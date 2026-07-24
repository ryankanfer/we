"use client";

import { useState } from "react";
import { useSession } from "@/lib/session";
import InterlockMark from "./InterlockMark";

export default function Pairing() {
  const { createCouple, joinCouple, signOut, busy, error, user } = useSession();
  const [code, setCode] = useState("");

  return (
    <div className="flex h-full flex-col justify-center">
      <div className="flex items-center gap-3">
        <InterlockMark size={34} overlap="touching" />
        <h1 className="font-serif text-[1.7rem] leading-snug">
          {user?.name ? `Hi ${user.name}.` : "One more step."}
        </h1>
      </div>
      <p className="mt-3 text-sm leading-relaxed text-faint">
        WE lives between two people. Start a shared space and invite your partner, or join the one
        they already made.
      </p>

      <button
        onClick={createCouple}
        disabled={busy}
        className="mt-8 w-full rounded-full bg-ink px-6 py-3.5 text-[15px] text-cream transition-opacity hover:opacity-90 disabled:opacity-40"
      >
        {busy ? "One moment…" : "Start our space"}
      </button>

      <div className="my-6 flex items-center gap-3 text-xs text-faint">
        <span className="h-px flex-1 bg-line" />
        or
        <span className="h-px flex-1 bg-line" />
      </div>

      <label className="block">
        <span className="text-[11px] uppercase tracking-[0.14em] text-faint">Join with a code</span>
        <input
          value={code}
          onChange={(e) => setCode(e.target.value.toUpperCase())}
          placeholder="6-character code"
          maxLength={6}
          className="mt-1.5 w-full rounded-xl border border-line bg-card px-4 py-3 text-center text-lg tracking-[0.3em] placeholder:tracking-normal placeholder:text-sm placeholder:text-faint/60 focus:border-ink focus:outline-none"
        />
      </label>
      <button
        onClick={() => joinCouple(code)}
        disabled={busy || code.length < 6}
        className="mt-3 w-full rounded-full border border-ink px-6 py-3 text-[15px] transition-colors hover:bg-ink hover:text-cream disabled:opacity-40"
      >
        Join their space
      </button>

      {error && <p className="mt-4 text-sm text-burgundy">{error}</p>}

      <button
        onClick={signOut}
        className="mt-8 text-center text-xs text-faint underline underline-offset-2 hover:text-ink"
      >
        Sign out
      </button>
    </div>
  );
}
