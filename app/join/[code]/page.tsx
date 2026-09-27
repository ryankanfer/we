import type { Metadata } from "next";
import JoinActions from "./JoinActions";

// The invitation, on the web.
//
// This page exists so the link in an invitation is a real https link that
// Messages, Mail and WhatsApp all make tappable. On an iPhone with WE
// installed, iOS opens the app directly and this page is never seen (the
// app claims /join/* through apple-app-site-association). Everyone else
// lands here: the sentence first, then the practical step.

type Params = { code: string };

function normalized(raw: string): string | null {
  const value = decodeURIComponent(raw)
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "")
    .slice(0, 16);
  return value.length > 0 ? value : null;
}

// Same answer the app gets: a name for a live invitation, nothing otherwise.
// A withdrawn, spent, expired or invented code all read as "someone".
async function inviterName(code: string): Promise<string | null> {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) return null;
  try {
    const response = await fetch(`${url}/rest/v1/rpc/invitation_greeting`, {
      method: "POST",
      headers: {
        apikey: key,
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ p_code: code }),
      cache: "no-store",
    });
    if (!response.ok) return null;
    const body = (await response.json()) as { name?: string } | null;
    const name = body?.name?.trim();
    return name ? name : null;
  } catch {
    return null;
  }
}

export async function generateMetadata({
  params,
}: {
  params: Promise<Params>;
}): Promise<Metadata> {
  const { code: raw } = await params;
  const code = normalized(raw);
  const name = code ? await inviterName(code) : null;
  const title = name ? `${name} is waiting for you in WE` : "You're invited to WE";
  const description = "A quiet place for the life you share. Tap to join.";
  return {
    title,
    description,
    openGraph: { title, description, siteName: "WE" },
    robots: { index: false, follow: false },
  };
}

export default async function JoinPage({ params }: { params: Promise<Params> }) {
  const { code: raw } = await params;
  const code = normalized(raw);
  const name = code ? await inviterName(code) : null;
  const testFlightURL = process.env.NEXT_PUBLIC_TESTFLIGHT_URL ?? null;

  return (
    <main
      className="flex min-h-dvh flex-col justify-between px-7 pb-12 pt-16"
      style={{
        color: "#F0EBDD",
        // The two lights, the same ones inside the app: the first thing the
        // person being invited sees of WE.
        background:
          "radial-gradient(60% 45% at 22% 105%, rgba(180,87,106,.55), transparent 70%)," +
          "radial-gradient(60% 45% at 78% 105%, rgba(138,169,139,.5), transparent 70%)," +
          "#0A0A09",
      }}
    >
      <p className="text-[13px] tracking-[0.3em]">WE</p>

      <div className="my-16">
        <h1 className="font-serif text-[44px] font-light leading-[1.08] tracking-tight">
          {name ? `${name} is waiting.` : "Someone is waiting for you."}
        </h1>
        <p className="mt-5 max-w-[32ch] font-serif text-[18px] leading-relaxed opacity-70">
          WE is one quiet place for the life you share. Make your own account, and you&rsquo;re
          in together.
        </p>

        {code && (
          <div
            className="mt-10 rounded-[18px] px-6 py-5"
            style={{
              background: "rgba(255,255,255,0.07)",
              border: "1px solid rgba(255,255,255,0.16)",
              backdropFilter: "blur(24px)",
              WebkitBackdropFilter: "blur(24px)",
            }}
          >
            <p className="text-[11px] tracking-[0.2em] opacity-60">YOUR CODE</p>
            <p className="mt-2 font-mono text-[30px] font-medium tracking-[0.25em]">{code}</p>
          </div>
        )}
      </div>

      <JoinActions code={code} testFlightURL={testFlightURL} />
    </main>
  );
}
