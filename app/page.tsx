// The public front door.
//
// WE is the iPhone app. This site used to be an early web version of it,
// which is frozen reference material now (see CLAUDE.md) and lives in git
// history. Invitation links point at this domain, so anyone who trims a link
// back to its root lands here rather than in a different, older WE.

export default function Home() {
  const testFlightURL = process.env.NEXT_PUBLIC_TESTFLIGHT_URL ?? null;

  return (
    <main
      className="flex min-h-dvh flex-col justify-between px-7 pb-12 pt-16"
      style={{
        color: "#F0EBDD",
        background:
          "radial-gradient(60% 45% at 22% 105%, rgba(180,87,106,.55), transparent 70%)," +
          "radial-gradient(60% 45% at 78% 105%, rgba(138,169,139,.5), transparent 70%)," +
          "#0A0A09",
      }}
    >
      <p className="text-[13px] tracking-[0.3em]">WE</p>

      <div className="my-16 max-w-xl">
        <h1 className="font-serif text-[44px] font-light leading-[1.08] tracking-tight">
          One place for the life you share.
        </h1>
        <p className="mt-5 max-w-[34ch] font-serif text-[18px] leading-relaxed opacity-70">
          WE is an iPhone app for two people. Plans, errands, the little things you mean to
          remember, all in one place you both can see.
        </p>
      </div>

      <div className="flex max-w-xl flex-col gap-3">
        {testFlightURL ? (
          <a
            href={testFlightURL}
            className="flex min-h-14 items-center justify-center rounded-[18px] text-[16px] font-semibold"
            style={{ background: "#F0EBDD", color: "#241F19" }}
          >
            Get WE on TestFlight
          </a>
        ) : (
          <p className="text-[15px] opacity-70">WE is in private testing.</p>
        )}
        <p className="text-[13px] leading-relaxed opacity-55">
          Got an invitation? Open the link on your iPhone, or enter the code in WE.
        </p>
      </div>
    </main>
  );
}
