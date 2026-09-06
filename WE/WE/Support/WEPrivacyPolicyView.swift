import SwiftUI

struct WEPrivacyPolicyView: View {
    static let publicURL = URL(
        string: "https://we-privacy-policy.kanfery.chatgpt.site"
    )!

    var showsCloseButton = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Privacy Policy")
                        .font(.largeTitle.weight(.semibold))
                    Text("Effective August 20, 2026")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                policySection(
                    "What WE keeps",
                    "WE keeps the account information needed to sign you in; "
                        + "the relationship, plans, responsibilities, and other "
                        + "content you choose to store; and limited operational "
                        + "records needed to keep the service reliable. Private "
                        + "answers and notes are owner-only and are never shown "
                        + "to a partner. WE does not sell personal data or use "
                        + "third-party advertising trackers."
                )

                policySection(
                    "OpenAI processing",
                    "A shared-direction question uses OpenAI only after you "
                        + "explicitly agree for that answer. WE sends your "
                        + "selected answer, the question, its available choices, "
                        + "and up to three lines of shared evidence. WE never "
                        + "sends your optional private note. OpenAI returns a "
                        + "proposed shared direction, which WE validates before "
                        + "saving. You can choose “Not now — don't send” instead."
                )

                policySection(
                    "OpenAI retention",
                    "WE requests no application-state storage by setting "
                        + "store=false. OpenAI does not train its models on API "
                        + "data by default. Unless WE's OpenAI project has "
                        + "approved Zero Data Retention or Modified Abuse "
                        + "Monitoring, OpenAI may retain API content for up to "
                        + "30 days for abuse monitoring. Until WE confirms an "
                        + "enhanced retention setting, you should assume that "
                        + "30-day maximum applies."
                )

                policySection(
                    "Service providers",
                    "Supabase provides authentication, database storage, realtime "
                        + "updates, and server functions. OpenAI processes only "
                        + "the explicitly permitted shared-direction payload "
                        + "described above. Apple processes information required "
                        + "to distribute the app and provide system services."
                )

                policySection(
                    "Retention and deletion",
                    "WE retains account and relationship data while the account "
                        + "is active or as needed to operate the service. You can "
                        + "delete your account inside the app. Deletion removes "
                        + "your account and private content; a former partner may "
                        + "retain a sanitized, read-only archive of content that "
                        + "was already shared. Legal or security obligations may "
                        + "require limited records to be retained longer."
                )

                policySection(
                    "Your choices",
                    "You can decline any shared-direction question, control the "
                        + "signals WE is allowed to notice, keep approved wording "
                        + "off external surfaces, sign out, or delete your account "
                        + "from the Account screen."
                )

                policySection(
                    "Contact",
                    "Questions or privacy requests can be sent to "
                        + (WEFeedbackReport.supportAddress ?? "the support address listed in the app")
                        + "."
                )

                Link(
                    "View this policy online",
                    destination: Self.publicURL
                )
                .font(.headline)
                .accessibilityIdentifier("privacy.policy.online")
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("privacy.policy")
    }

    private func policySection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack { WEPrivacyPolicyView() }
}
