"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { AnimatePresence } from "framer-motion";
import { useSession } from "@/lib/session";
import InterlockMark from "./InterlockMark";
import Onboarding from "./Onboarding";
import Splash from "./Splash";
import Auth from "./Auth";
import Pairing from "./Pairing";

const INTRO_KEY = "we-intro-seen";

export default function AppShell({ children }: { children: React.ReactNode }) {
  const [mounted, setMounted] = useState(false);
  const [splashDone, setSplashDone] = useState(false);
  const [introSeen, setIntroSeen] = useState(true);

  const status = useSession((s) => s.status);
  const user = useSession((s) => s.user);
  const announcement = useSession((s) => s.announcement);
  const signOut = useSession((s) => s.signOut);

  useEffect(() => {
    setMounted(true);
    setIntroSeen(typeof window !== "undefined" && localStorage.getItem(INTRO_KEY) === "1");
    useSession.getState().init();
  }, []);

  const finishSplash = useCallback(() => setSplashDone(true), []);
  const finishIntro = useCallback(() => {
    localStorage.setItem(INTRO_KEY, "1");
    setIntroSeen(true);
  }, []);

  const showSplash = mounted && (!splashDone || status === "loading");
  const signedOut = status === "signedOut";
  const showOnboarding = mounted && !showSplash && signedOut && !introSeen;
  const chrome = mounted && !showSplash && status === "ready";

  let body: React.ReactNode = <div key="blank" aria-hidden="true" />;
  if (mounted) {
    if (showSplash) body = <Splash key="splash" onDone={finishSplash} />;
    else if (status === "unconfigured") body = <Unconfigured key="unconfigured" />;
    else if (showOnboarding) body = <Onboarding key="onboarding" onDone={finishIntro} />;
    else if (signedOut) body = <Auth key="auth" />;
    else if (status === "needsCouple") body = <Pairing key="pairing" />;
    else if (status === "ready") body = <div key="app">{children}</div>;
  }

  return (
    <div className="flex min-h-dvh flex-col items-center gap-4 px-3 py-4 sm:py-8">
      <div className="flex w-full max-w-[430px] flex-1 flex-col overflow-hidden rounded-[2rem] border border-line bg-cream shadow-[0_1px_2px_rgba(39,33,26,0.06)]">
        {chrome && (
          <header className="flex items-center justify-between px-6 pb-2 pt-6">
            <Link href="/" className="flex items-center gap-2.5" aria-label="WE home">
              <InterlockMark size={26} overlap="interlocked" />
              <span className="font-serif text-lg tracking-[0.18em]">WE</span>
            </Link>
            <span className="text-xs text-faint">{user?.name}</span>
          </header>
        )}

        <main className="flex-1 overflow-y-auto px-6 pb-8 pt-2">
          <AnimatePresence mode="wait">{body}</AnimatePresence>
        </main>
      </div>

      <div aria-live="polite" className="sr-only">
        {mounted ? announcement : ""}
      </div>

      {chrome && (
        <aside className="w-full max-w-[430px] rounded-xl border border-dashed border-faint/40 bg-outer px-4 py-2.5 text-xs text-faint">
          <span>Signed in as {user?.name}</span>
          <button onClick={signOut} className="ml-3 underline underline-offset-2 hover:text-ink">
            Sign out
          </button>
        </aside>
      )}
    </div>
  );
}

function Unconfigured() {
  return (
    <div className="flex h-full flex-col items-center justify-center text-center">
      <InterlockMark size={48} overlap="apart" />
      <p className="mt-6 font-serif text-xl">Not connected yet.</p>
      <p className="mt-2 max-w-[28ch] text-sm text-faint">
        Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY to bring WE online.
      </p>
    </div>
  );
}
