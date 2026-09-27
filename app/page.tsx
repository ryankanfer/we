// The public front door.
//
// WE is the iPhone app. Invitation links point at this domain, so anyone who
// trims a link back to its root lands here. One screen that says what WE is,
// three short moments that show how it works, and a way in.

import type { Metadata } from "next";
import SiteFrame, { LightsMark } from "@/components/site/SiteFrame";

export const metadata: Metadata = {
  title: "WE. One place for the life you share.",
  description: "An iPhone app for two people. Plans, errands, and the little things you mean to remember, in one place you both can see.",
  openGraph: {
    title: "WE",
    description: "One place for the life you share.",
    siteName: "WE",
  },
};

const moments = [
  {
    reading: "together" as const,
    title: "Say it like a text.",
    body: "Dinner with your parents Sunday. Call the plumber. The book she mentioned. Type it how you would say it, and WE puts it where it belongs.",
  },
  {
    reading: "alone" as const,
    title: "Shared, or just yours for now.",
    body: "Everything is shared by default. Mark something Only me and it waits with you until you are ready, with a day to be asked again if you like. Time, not a wall.",
  },
  {
    reading: "merged" as const,
    title: "Decide together.",
    body: "When something needs both of you, each says yes in your own time. When you both do, it is settled, and you both see it.",
  },
];

export default function Home() {
  const testFlightURL = process.env.NEXT_PUBLIC_TESTFLIGHT_URL ?? null;

  const cta = testFlightURL ? (
    <a
      href={testFlightURL}
      className="inline-flex min-h-14 items-center justify-center rounded-full px-8 text-[16px] font-semibold transition-transform hover:scale-[1.02]"
      style={{ background: "#F0EBDD", color: "#241F19" }}
    >
      Get WE on TestFlight
    </a>
  ) : (
    <p className="text-[15px] opacity-70">WE is in private testing.</p>
  );

  return (
    <SiteFrame>
      <main className="mx-auto max-w-5xl px-6 sm:px-10">
        <section className="flex min-h-[78vh] flex-col justify-center py-20">
          <p className="we-rise text-[12px] tracking-[0.3em] opacity-60">AN IPHONE APP FOR TWO</p>
          <h1 className="we-rise we-rise-2 mt-5 max-w-[14ch] font-serif text-[48px] font-light leading-[1.04] tracking-tight sm:text-[72px]">
            One place for the life you share.
          </h1>
          <p className="we-rise we-rise-3 mt-6 max-w-[38ch] font-serif text-[19px] leading-relaxed opacity-70">
            Plans, errands, and the little things you mean to remember. One quiet place you both can see, and nothing to keep score.
          </p>
          <div className="we-rise we-rise-3 mt-10 flex flex-col items-start gap-4">
            {cta}
            <p className="text-[13px] opacity-55">Got an invitation? Open the link on your iPhone.</p>
          </div>
        </section>

        <section aria-labelledby="how" className="py-16">
          <h2 id="how" className="text-[12px] tracking-[0.3em] opacity-60">HOW IT WORKS</h2>
          <div className="mt-8 grid gap-4 sm:grid-cols-3">
            {moments.map((m) => (
              <article key={m.title} className="we-glass rounded-[26px] p-7">
                <LightsMark reading={m.reading} />
                <h3 className="mt-5 font-serif text-[23px] font-normal leading-snug">{m.title}</h3>
                <p className="mt-3 text-[15px] leading-relaxed opacity-70">{m.body}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="py-20">
          <div className="max-w-2xl">
            <h2 className="font-serif text-[34px] font-light leading-tight sm:text-[44px]">Two lights.</h2>
            <p className="mt-5 font-serif text-[19px] leading-relaxed opacity-70">
              You each have one. Where they overlap is what you share. They move only when something happens between you: someone arrives, something is added, you decide together. They never count, compare, or keep score.
            </p>
          </div>
        </section>

        <section className="flex flex-col items-start gap-6 py-16">
          <h2 className="font-serif text-[34px] font-light sm:text-[44px]">Made for two.</h2>
          {cta}
        </section>
      </main>
    </SiteFrame>
  );
}
