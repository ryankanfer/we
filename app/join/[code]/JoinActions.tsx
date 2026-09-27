"use client";

import { useState } from "react";

// Open WE if it is installed, get it if not, and the code by hand as the
// last resort. The custom scheme is the fallback for the rare case iOS does
// not hand the https link straight to the app (for example after a long
// press, or when the link was pasted into Safari).
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
          Open WE
        </a>
      )}
      {testFlightURL && (
        <a
          href={testFlightURL}
          className="flex min-h-14 items-center justify-center rounded-[18px] text-[16px] font-semibold"
          style={{ border: "1px solid rgba(240,235,221,0.22)", background: "rgba(255,255,255,0.06)" }}
        >
          Get WE
        </a>
      )}
      {code && (
        <button
          type="button"
          onClick={copy}
          className="min-h-11 text-[15px] opacity-75"
        >
          {copied ? "Copied" : "Copy the code"}
        </button>
      )}
      <p className="mt-2 text-center text-[13px] leading-relaxed opacity-55">
        Already have WE? Open it, tap &ldquo;Someone invited me&rdquo;, and enter the code.
      </p>
    </div>
  );
}
