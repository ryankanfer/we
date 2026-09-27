// Support: the handful of questions people actually ask, and a way to reach
// a person. App Store Connect links here as the Support URL.

import type { Metadata } from "next";
import SiteFrame, { CONTACT } from "@/components/site/SiteFrame";

export const metadata: Metadata = {
  title: "Support · WE",
  description: "Help with invitations, email, Only me, and your account.",
};

const questions: { q: string; a: React.ReactNode }[] = [
  {
    q: "How do we get set up?",
    a: "One of you makes an account and sends an invitation from the app. The other opens the link on their iPhone, makes their own account, and you are in together.",
  },
  {
    q: "The invitation link didn't open the app.",
    a: "Make sure WE is installed, then tap the link again from Messages or Mail. You can also open WE, tap “Someone invited me”, and type the code from the invitation page.",
  },
  {
    q: "I didn't get the confirmation email.",
    a: "Check spam and promotions, then use “Send it again” in the app. If you confirmed on another device, choose “I verified on another device” and sign in.",
  },
  {
    q: "We both sent each other an invitation.",
    a: "No harm done. On the waiting screen, enter the code they sent you and tap Join their space. Your own empty space is set aside and you join theirs.",
  },
  {
    q: "What does Only me mean?",
    a: "Only me keeps something with you until you're ready to share it. You can pick a day to be asked again. It's time, not a wall: nothing is hidden forever, and your partner never sees it until you share it.",
  },
  {
    q: "How do I delete my account?",
    a: "In WE, open Account and choose Delete account. Your account and anything private are removed. Anything you already shared stays with your partner as a read-only archive.",
  },
];

export default function Support() {
  return (
    <SiteFrame>
      <main className="mx-auto max-w-2xl px-6 pb-10 pt-16 sm:px-10">
        <p className="text-[12px] tracking-[0.3em] opacity-60">SUPPORT</p>
        <h1 className="mt-4 font-serif text-[40px] font-light leading-tight">How can we help?</h1>

        <div className="mt-10 flex flex-col gap-3">
          {questions.map(({ q, a }) => (
            <details key={q} className="we-glass group rounded-[22px] px-6 py-5">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-4 font-serif text-[19px]">
                {q}
                <span aria-hidden className="text-[20px] opacity-50 transition-transform group-open:rotate-45">+</span>
              </summary>
              <p className="mt-3 text-[15px] leading-relaxed opacity-70">{a}</p>
            </details>
          ))}
        </div>

        <div className="we-glass mt-10 rounded-[22px] px-6 py-6">
          <p className="font-serif text-[19px]">Still stuck?</p>
          <p className="mt-2 text-[15px] leading-relaxed opacity-70">
            Write to <a className="underline underline-offset-4" href={`mailto:${CONTACT}`}>{CONTACT}</a>. A person reads every message. In the app, you can also use Send feedback in Account.
          </p>
        </div>
      </main>
    </SiteFrame>
  );
}
