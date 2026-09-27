import { ImageResponse } from "next/og";

// The picture Messages shows under an invitation link: the two lights, and
// who is waiting. The person being invited sees WE before they have it.

export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
export const alt = "An invitation to WE";

async function inviterName(code: string): Promise<string | null> {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) return null;
  try {
    const response = await fetch(`${url}/rest/v1/rpc/invitation_greeting`, {
      method: "POST",
      headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({ p_code: code.toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 16) }),
      cache: "no-store",
    });
    if (!response.ok) return null;
    const body = (await response.json()) as { name?: string } | null;
    return body?.name?.trim() || null;
  } catch {
    return null;
  }
}

export default async function Image({ params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  const name = await inviterName(code);
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          padding: "72px 84px",
          color: "#F0EBDD",
          background:
            "radial-gradient(55% 60% at 30% 110%, rgba(180,87,106,.75), rgba(10,10,9,0) 70%)," +
            "radial-gradient(55% 60% at 70% 110%, rgba(138,169,139,.7), rgba(10,10,9,0) 70%)," +
            "#0A0A09",
        }}
      >
        <div style={{ fontSize: 28, letterSpacing: 10 }}>WE</div>
        <div style={{ fontSize: 96, lineHeight: 1.02, letterSpacing: -3, fontWeight: 300 }}>
          {name ? `${name} is waiting.` : "Someone is waiting for you."}
        </div>
      </div>
    ),
    size,
  );
}
