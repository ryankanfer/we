// The public site's frame: the dark ground, the two lights, a quiet header
// and footer. The lights arrive apart and drift together once on load, the
// same move the app makes when it opens. They do not loop.

import Link from "next/link";

export const CONTACT = "kanfer.ryan@gmail.com";

export default function SiteFrame({ children }: { children: React.ReactNode }) {
  return (
    <div className="we-site relative min-h-dvh overflow-x-hidden" style={{ color: "#F0EBDD", background: "#0A0A09" }}>
      <div aria-hidden className="we-lights pointer-events-none fixed inset-x-0 bottom-0 h-[70vh]">
        <span className="we-light we-light-a" />
        <span className="we-light we-light-b" />
      </div>

      <header className="relative z-10 mx-auto flex max-w-5xl items-center justify-between px-6 pt-8 sm:px-10">
        <Link href="/" className="text-[13px] tracking-[0.34em]" aria-label="WE home">
          WE
        </Link>
        <nav className="flex gap-6 text-[14px] opacity-70">
          <Link href="/privacy" className="hover:opacity-100">Privacy</Link>
          <Link href="/support" className="hover:opacity-100">Support</Link>
        </nav>
      </header>

      <div className="relative z-10">{children}</div>

      <footer className="relative z-10 mx-auto flex max-w-5xl flex-col gap-3 px-6 pb-10 pt-20 text-[13px] opacity-55 sm:flex-row sm:items-center sm:justify-between sm:px-10">
        <p>WE. Made for two.</p>
        <div className="flex gap-6">
          <Link href="/privacy">Privacy</Link>
          <Link href="/support">Support</Link>
          <a href={`mailto:${CONTACT}`}>Contact</a>
        </div>
      </footer>
    </div>
  );
}

/// The lights as a small inline mark. Three readings, each one sentence:
/// together, only yours, decided together.
export function LightsMark({ reading }: { reading: "together" | "alone" | "merged" }) {
  const a = "#B4576A";
  const b = "#8AA98B";
  return (
    <svg width="64" height="28" viewBox="0 0 64 28" aria-hidden>
      <defs>
        <radialGradient id={`ga-${reading}`}><stop offset="0" stopColor={a} /><stop offset="1" stopColor={a} stopOpacity="0" /></radialGradient>
        <radialGradient id={`gb-${reading}`}><stop offset="0" stopColor={b} /><stop offset="1" stopColor={b} stopOpacity="0" /></radialGradient>
      </defs>
      {reading === "together" && (<><circle cx="24" cy="14" r="13" fill={`url(#ga-${reading})`} /><circle cx="40" cy="14" r="13" fill={`url(#gb-${reading})`} /></>)}
      {reading === "alone" && (<><circle cx="24" cy="14" r="13" fill={`url(#ga-${reading})`} /><circle cx="44" cy="14" r="6" fill="none" stroke={b} strokeOpacity=".45" strokeDasharray="2 3" /></>)}
      {reading === "merged" && (<><circle cx="30" cy="14" r="13" fill={`url(#ga-${reading})`} /><circle cx="34" cy="14" r="13" fill={`url(#gb-${reading})`} style={{ mixBlendMode: "screen" }} /></>)}
    </svg>
  );
}
