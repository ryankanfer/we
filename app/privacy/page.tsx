// The privacy policy. Mirrors WEPrivacyPolicyView in the app; change both
// together, and move the effective date when the substance changes.

import type { Metadata } from "next";
import SiteFrame, { CONTACT } from "@/components/site/SiteFrame";

export const metadata: Metadata = {
  title: "Privacy · WE",
  description: "What WE keeps, who processes it, and the choices you have.",
};

export default function Privacy() {
  return (
    <SiteFrame>
      <main className="we-prose mx-auto max-w-2xl px-6 pb-10 pt-16 sm:px-10">
        <p className="text-[12px] tracking-[0.3em] opacity-60">PRIVACY POLICY</p>
        <h1 className="mt-4 font-serif text-[40px] font-light leading-tight">Yours stays yours.</h1>
        <p>Effective September 27, 2026</p>

        <h2>What WE keeps</h2>
        <p>
          WE keeps the account information needed to sign you in; the relationship, plans,
          responsibilities, and other content you choose to store; and limited operational records
          needed to keep the service reliable. Anything private, including anything you mark Only
          me and the day you choose to be asked about sharing it, is visible only to you and is
          never shown to a partner. WE does not sell personal data or use third-party advertising
          trackers.
        </p>

        <h2>OpenAI processing</h2>
        <p>
          A shared-direction question uses OpenAI only after you explicitly agree for that answer.
          WE sends your selected answer, the question, its available choices, and up to three lines
          of shared evidence. WE never sends your optional private note. OpenAI returns a proposed
          shared direction, which WE validates before saving. You can choose &ldquo;Not now, don&rsquo;t
          send&rdquo; instead.
        </p>

        <h2>OpenAI retention</h2>
        <p>
          WE requests no application-state storage by setting store=false. OpenAI does not train
          its models on API data by default. Unless WE&rsquo;s OpenAI project has approved Zero Data
          Retention or Modified Abuse Monitoring, OpenAI may retain API content for up to 30 days
          for abuse monitoring. Until WE confirms an enhanced retention setting, you should assume
          that 30-day maximum applies.
        </p>

        <h2>Service providers</h2>
        <p>
          Supabase provides authentication, database storage, realtime updates, and server
          functions. OpenAI processes only the explicitly permitted shared-direction payload
          described above. Resend sends account emails, such as confirming your address and
          resetting your password; it receives your email address and nothing else. Vercel hosts
          this site and the invitation page: when someone opens an invitation link, the page shows
          the first name of the person who sent it, and only while the invitation is live. Apple
          processes information required to distribute the app and provide system services.
        </p>

        <h2>Retention and deletion</h2>
        <p>
          WE retains account and relationship data while the account is active or as needed to
          operate the service. You can delete your account inside the app. Deletion removes your
          account and private content; a former partner may retain a sanitized, read-only archive
          of content that was already shared. Legal or security obligations may require limited
          records to be retained longer.
        </p>

        <h2>Your choices</h2>
        <p>
          You can decline any shared-direction question, control the signals WE is allowed to
          notice, keep approved wording off external surfaces, sign out, or delete your account
          from the Account screen.
        </p>

        <h2>Contact</h2>
        <p>
          Questions or privacy requests can be sent to <a href={`mailto:${CONTACT}`}>{CONTACT}</a>.
        </p>
      </main>
    </SiteFrame>
  );
}
