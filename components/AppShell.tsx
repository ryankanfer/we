"use client";

import { useCallback, useEffect, useState } from "react";
import { AnimatePresence } from "framer-motion";
import { useSession } from "@/lib/session";
import InterlockMark from "./InterlockMark";
import Onboarding from "./Onboarding";
import Splash from "./Splash";
import Auth from "./Auth";
import Pairing from "./Pairing";
import { Sidebar, BottomBar } from "./Nav";

const INTRO_KEY = "we-intro-seen";

export default function AppShell({ children }: { children: React.ReactNode }) {
  const [mounted, setMounted] = useState(false);
  const [splashDone, setSplashDone] = useState(false);
  const [introSeen, setIntroSeen] = useState(true);

  const status = useSession((s) => s.status);
  const announcement = useSession((s) => s.announcement);

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
  const ready = mounted && !showSplash && status === "ready";

  // Full-screen, centered flows (splash / intro / auth / pairing).
  let flow: React.ReactNode = null;
  if (!mounted) flow = <div aria-hidden="true" />;
  else if (showSplash) flow = <Splash key="splash" onDone={finishSplash} />;
  else if (status === "unconfigured") flow = <Unconfigured key="unconfigured" />;
  else if (showOnboarding) flow = <Onboarding key="onboarding" onDone={finishIntro} />;
  else if (signedOut) flow = <Auth key="auth" />;
  else if (status === "needsCouple") flow = <Pairing key="pairing" />;

  return (
    <>
      {ready ? (
        <div className="flex min-h-dvh-safe">
          <Sidebar />
          <div className="flex min-w-0 flex-1 flex-col">
            <main className="mx-auto w-full max-w-5xl flex-1 px-5 pb-28 pt-6 md:px-10 md:pb-12 md:pt-10">
              {children}
            </main>
          </div>
          <BottomBar />
        </div>
      ) : (
        <div className="mx-auto flex min-h-dvh-safe w-full max-w-md flex-col px-6 pt-safe">
          <AnimatePresence mode="wait">{flow}</AnimatePresence>
        </div>
      )}

      <div aria-live="polite" className="sr-only">
        {mounted ? announcement : ""}
      </div>
    </>
  );
}

function Unconfigured() {
  return (
    <div className="flex h-dvh flex-col items-center justify-center text-center">
      <InterlockMark size={48} overlap="apart" />
      <p className="mt-6 font-serif text-xl">Not connected yet.</p>
      <p className="mt-2 max-w-[28ch] text-sm text-faint">
        Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY to bring WE online — or add
        <span className="font-medium"> ?demo=1</span> to the URL to explore with sample data.
      </p>
    </div>
  );
}
