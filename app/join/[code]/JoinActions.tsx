"use client";

import { useState } from "react";

// Two paths, stated plainly, because the web cannot tell whether WE is
// installed. Have it: open it. Don't: get it first, then come back to this
// same link. iOS has no way to carry the code through an install, so "Get
// WE" also copies the code on the way out, and the page says to return.
export default function JoinActions({
  code,
  testFlightURL,
}: {
  code: string | null;
  testFlightURL: string | null;
}) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    if (!code) return;
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Selection still works; the code is on screen.
    }
  }

  return (
    <div className="flex flex-col gap-3">
      {code && (
        <a
          href={`we://join/${code}`}
          className="flex min-h-14 items-center justify-center rounded-[18px] text-[16px] font-semibold"
          style={{ background: "#F0EBDD", color: "#241F19" }}
        >
          I have WE. Open it.
        </a>
      )}

      {testFlightURL && (
        <div
          className="mt-3 rounded-[18px] px-5 py-5"
          style={{ border: "1px solid rgba(240,235,221,0.16)", background: "rgba(255,255,255,0.05)" }}
        >
          <p className="text-[15px] font-semibold">Don&rsquo;t have WE yet?</p>
          <ol className="mt-2 list-decimal space-y-1 pl-5 text-[14px] leading-relaxed opacity-75">
            <li>Get it from TestFlight, Apple&rsquo;s app for early versions.</li>
            <li>Come back to this link and tap the button above.</li>
          </ol>
          <a
            href={testFlightURL}
            onClick={copy}
            className="mt-4 flex min-h-12 items-center justify-center rounded-[14px] text-[15px] font-semibold"
            style={{ border: "1px solid rgba(240,235,221,0.22)", background: "rgba(255,255,255,0.06)" }}
          >
            Get WE on TestFlight
          </a>
        </div>
      )}

      {code && (
        <button type="button" onClick={copy} className="min-h-11 text-[15px] opacity-75">
          {copied ? "Copied" : "Copy the code"}
        </button>
      )}
      <p className="mt-1 text-center text-[13px] leading-relaxed opacity-55">
        Link not opening WE? Open the app, tap &ldquo;Someone invited me&rdquo;, and enter the code.
      </p>
    </div>
  );
}
