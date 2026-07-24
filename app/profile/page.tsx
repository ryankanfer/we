"use client";

import { useSession } from "@/lib/session";
import { Card, SectionLabel } from "@/components/ui";
import Icon from "@/components/Icon";
import InterlockMark from "@/components/InterlockMark";

const PROMISE = [
  "Some things stay yours until you both choose to open them — together.",
  "“Not now” is always safe. No one is told, and no one keeps count.",
  "WE describes patterns. It never diagnoses people, and it never scores you.",
  "The better things are, the quieter WE becomes.",
];

export default function Profile() {
  const user = useSession((s) => s.user);
  const couple = useSession((s) => s.couple);
  const members = useSession((s) => s.members);
  const viewer = useSession((s) => s.viewer);
  const demo = useSession((s) => s.demo);
  const signOut = useSession((s) => s.signOut);
  const setViewer = useSession((s) => s.setViewer);

  const partner = members.find((m) => m.id !== viewer);

  return (
    <div>
      <h1 className="font-serif text-[2rem] leading-tight md:text-[2.4rem]">Profile</h1>

      <div className="mt-6 grid gap-7 lg:grid-cols-2">
        <div className="space-y-7">
          <Card className="flex items-center gap-4">
            <span className="grid h-14 w-14 place-items-center rounded-full bg-burgundy-soft text-lg text-burgundy">
              {(user?.name ?? "U").slice(0, 1)}
            </span>
            <div>
              <p className="font-serif text-xl">{user?.name}</p>
              <p className="text-sm text-faint">
                {partner ? `Paired with ${partner.name}` : "Waiting for your partner to join"}
              </p>
            </div>
          </Card>

          <section>
            <SectionLabel>Your shared space</SectionLabel>
            <Card className="flex items-center gap-3">
              <InterlockMark size={28} overlap="interlocked" />
              <div>
                <p className="text-[15px]">
                  {members.length >= 2 ? "Two of you, one space" : "Just you, so far"}
                </p>
                {couple && members.length < 2 && (
                  <p className="text-sm text-faint">
                    Invite code: <span className="font-serif tracking-[0.2em]">{couple.joinCode}</span>
                  </p>
                )}
              </div>
            </Card>
          </section>

          {demo ? (
            <section>
              <SectionLabel>Experience as (demo)</SectionLabel>
              <div className="flex gap-2">
                {members.map((m) => (
                  <button
                    key={m.id}
                    onClick={() => setViewer(m.id)}
                    aria-pressed={viewer === m.id}
                    className={`rounded-full border px-4 py-2 text-sm transition-colors ${
                      viewer === m.id ? "border-ink bg-ink text-cream" : "border-line hover:border-ink"
                    }`}
                  >
                    {m.name}
                  </button>
                ))}
              </div>
              <p className="mt-2 text-xs text-faint">
                Sample data — flip between the two of you to feel both sides of a reveal.
              </p>
            </section>
          ) : (
            <button
              onClick={signOut}
              className="flex items-center gap-2 text-sm text-faint underline underline-offset-2 hover:text-ink"
            >
              <Icon name="profile" size={16} /> Sign out
            </button>
          )}
        </div>

        <section>
          <SectionLabel>The promise</SectionLabel>
          <Card>
            <ul className="space-y-4">
              {PROMISE.map((l) => (
                <li key={l} className="flex items-start gap-3">
                  <span className="mt-[0.6em] h-1 w-1 shrink-0 rounded-full bg-ink/40" aria-hidden="true" />
                  <p className="font-serif text-[1.02rem] leading-relaxed text-ink/85">{l}</p>
                </li>
              ))}
            </ul>
          </Card>
        </section>
      </div>
    </div>
  );
}
