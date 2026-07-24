"use client";

import { useState } from "react";
import { useSession } from "@/lib/session";
import InterlockMark from "./InterlockMark";

export default function Auth() {
  const { signIn, signUp, busy, error, info } = useSession();
  const [mode, setMode] = useState<"in" | "up">("up");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");

  const submit = () => {
    if (mode === "up") signUp(email, password, name);
    else signIn(email, password);
  };

  return (
    <div className="flex h-full flex-col justify-center">
      <div className="flex items-center gap-2.5">
        <InterlockMark size={26} overlap="interlocked" />
        <span className="font-serif text-lg tracking-[0.18em]">WE</span>
      </div>
      <h1 className="mt-6 font-serif text-[1.7rem] leading-snug">
        {mode === "up" ? "Make your sign-in." : "Welcome back."}
      </h1>
      <p className="mt-2 text-sm leading-relaxed text-faint">
        {mode === "up"
          ? "Yours alone. Your partner makes theirs; you meet in one shared space."
          : "Pick up where the two of you left off."}
      </p>

      <div className="mt-7 space-y-3">
        {mode === "up" && (
          <Field label="Your name" value={name} onChange={setName} placeholder="Ry" autoComplete="given-name" />
        )}
        <Field label="Email" value={email} onChange={setEmail} placeholder="you@email.com" type="email" autoComplete="email" />
        <Field
          label="Password"
          value={password}
          onChange={setPassword}
          placeholder="••••••••"
          type="password"
          autoComplete={mode === "up" ? "new-password" : "current-password"}
        />
      </div>

      {error && <p className="mt-4 text-sm text-burgundy">{error}</p>}
      {info && <p className="mt-4 text-sm text-sage">{info}</p>}

      <button
        onClick={submit}
        disabled={busy || !email || !password || (mode === "up" && !name)}
        className="mt-6 w-full rounded-full bg-ink px-6 py-3.5 text-[15px] text-cream transition-opacity hover:opacity-90 disabled:opacity-40"
      >
        {busy ? "One moment…" : mode === "up" ? "Create sign-in" : "Sign in"}
      </button>

      <button
        onClick={() => setMode(mode === "up" ? "in" : "up")}
        className="mt-4 text-center text-xs text-faint underline underline-offset-2 hover:text-ink"
      >
        {mode === "up" ? "I already have a sign-in" : "I'm new here"}
      </button>
    </div>
  );
}

function Field({
  label,
  value,
  onChange,
  placeholder,
  type = "text",
  autoComplete,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  type?: string;
  autoComplete?: string;
}) {
  return (
    <label className="block">
      <span className="text-[11px] uppercase tracking-[0.14em] text-faint">{label}</span>
      <input
        type={type}
        value={value}
        autoComplete={autoComplete}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="mt-1.5 w-full rounded-xl border border-line bg-card px-4 py-3 text-[15px] placeholder:text-faint/60 focus:border-ink focus:outline-none"
      />
    </label>
  );
}
