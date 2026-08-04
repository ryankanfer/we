//
//  WEFeedbackView.swift
//  WE
//
//  The one way to tell someone the app went wrong.
//
//  It is built on `MFMailComposeViewController` rather than a `mailto:` URL
//  for a single reason that decides the whole screen: a `mailto:` URL cannot
//  carry an attachment. A crash report that cannot travel with the sentence
//  describing it is two messages nobody will reconcile.
//
//  The shape follows the rule already set at
//  `FieldOutreachConfirmation.swift:213` — the app shows what is about to
//  leave, in full, before anything leaves. There is no "diagnostics may
//  include…" hedge here because the contents are on the screen. If that list
//  ever grows to where it cannot be read, the list is wrong, not the screen.
//

import MessageUI
import os
import SwiftUI

@MainActor
struct WEFeedbackView: View {
    @Environment(\.dismiss) private var dismiss

    /// Supplied by the caller so this screen never reaches for a session it
    /// might not have — feedback has to work before pairing, and after
    /// something has already gone wrong.
    let accountID: String?
    let email: String?

    private let store = WEDiagnosticsStore()

    @State private var note = ""
    @State private var showsMail = false
    @State private var showsShare = false
    @State private var showsAttachment = false
    @State private var sent = false
    @State private var failure: String?

    private var report: WEFeedbackReport {
        WEFeedbackReport(
            note: note,
            accountID: accountID,
            email: email,
            diagnostics: diagnosticLines,
            attachment: store.combinedJSON()
        )
    }

    /// Read once per appearance rather than per body evaluation — this walks
    /// the directory and parses every stored payload.
    @State private var diagnosticLines: [String] = []

    var body: some View {
        ZStack {
            FieldPalette.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, FieldMetrics.sectionGap)

                    editor
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    leaving
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    actions
                }
                .padding(.top, FieldMetrics.screenTop)
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.bottom, 60)
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("field.feedback")
        .overlay(alignment: .topTrailing) { closeButton }
        .task { diagnosticLines = Self.summaries(in: store) }
        .sheet(isPresented: $showsMail) {
            WEMailComposer(
                report: report,
                recipient: WEFeedbackReport.supportAddress
            ) { result in
                switch result {
                case .sent:
                    sent = true
                    dismiss()
                case .failed(let message):
                    failure = message
                case .cancelled:
                    break
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsShare) {
            if let items = shareItems() {
                WEShareSheet(items: items)
            }
        }
        .sheet(isPresented: $showsAttachment) {
            WEAttachmentPreview(data: report.attachment)
        }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Text("Done")
                .font(FieldType.subLabel)
                .tracking(FieldTracking.subLabel)
                .textCase(.uppercase)
                .foregroundStyle(.fieldInk(.recessive))
                .padding(18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("field.feedback.done")
    }

    // MARK: The ask

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            FieldLabel("Feedback")

            Text("What went wrong?")
                .font(FieldType.pageHeadline)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.16, size: 32)
                .fixedSize(horizontal: false, vertical: true)

            Text("Say it however you'd say it out loud. What you were doing "
                 + "matters more than what you think broke.")
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.sectionSubtitle))
                .fieldLineHeight(1.6, size: 14.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var editor: some View {
        TextEditor(text: $note)
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.headline))
            .scrollContentBackground(.hidden)
            .frame(minHeight: 140, alignment: .topLeading)
            .padding(14)
            .background(
                FieldPalette.ink.opacity(0.06),
                in: RoundedRectangle(
                    cornerRadius: FieldMetrics.cardRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: FieldMetrics.cardRadius,
                    style: .continuous
                )
                .stroke(FieldRule.primary, lineWidth: 1)
            }
            .accessibilityIdentifier("field.feedback.note")
            .accessibilityLabel("What went wrong")
    }

    // MARK: What leaves

    private var leaving: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            FieldLabel("What gets sent")
                .padding(.top, 20)
                .padding(.bottom, 6)

            Text("This, and nothing else. Nothing either of you has written "
                 + "in the app is in here.")
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.sectionSubtitle))
                .fieldLineHeight(1.6, size: 14.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

            ForEach(report.environmentLines, id: \.self) { line in
                contents(line)
            }
            ForEach(report.accountLines, id: \.self) { line in
                contents(line)
            }

            if diagnosticLines.isEmpty {
                contents("No crashes or hangs recorded")
            } else {
                ForEach(diagnosticLines, id: \.self) { line in
                    contents(line)
                }
            }

            if let attachment = report.attachment {
                attachmentRow(bytes: attachment.count)
            }
        }
        .accessibilityIdentifier("field.feedback.contents")
    }

    private func contents(_ line: String) -> some View {
        Text(line)
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.metadataProse))
            .fieldLineHeight(1.5, size: 14.5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 11)
            .overlay(alignment: .top) { FieldRuleLine(color: FieldRule.row) }
    }

    /// The one part that is too long to read in place, so it is named, sized,
    /// and openable. Attaching something unopenable would defeat the point of
    /// showing the rest.
    private func attachmentRow(bytes: Int) -> some View {
        Button { showsAttachment = true } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(
                    "\(WEFeedbackReport.attachmentFilename) · "
                        + WEFeedbackReport.formatted(bytes: bytes)
                )
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.metadataProse))

                Spacer(minLength: 12)

                Text("Read it")
                    .font(FieldType.subLabel)
                    .tracking(FieldTracking.subLabel)
                    .textCase(.uppercase)
                    .foregroundStyle(.fieldInk(.recessive))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { FieldRuleLine(color: FieldRule.row) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("field.feedback.attachment")
    }

    // MARK: Sending

    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()
                .padding(.bottom, 20)

            if canSendMail {
                Button("Send") { showsMail = true }
                    .buttonStyle(FieldOutlinedButtonStyle())
                    .disabled(!report.isSendable)
                    .opacity(report.isSendable ? 1 : 0.4)
                    .accessibilityIdentifier("field.feedback.send")
                    .padding(.bottom, 14)
            } else {
                // No mail account on the phone. Rather than a dead Send
                // button and an explanation, the action becomes the one that
                // works — the Share Sheet carries the same body and the same
                // file to whatever the person does have.
                Button("Send it another way") { showsShare = true }
                    .buttonStyle(FieldOutlinedButtonStyle())
                    .disabled(!report.isSendable)
                    .opacity(report.isSendable ? 1 : 0.4)
                    .accessibilityIdentifier("field.feedback.share")
                    .padding(.bottom, 14)

                Text("There's no mail account set up on this phone, so this "
                     + "hands it to whatever you use instead.")
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .fieldLineHeight(1.5, size: 13)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)
            }

            Button("Not now") { dismiss() }
                .buttonStyle(FieldQuietButtonStyle())
                .accessibilityIdentifier("field.feedback.cancel")

            if let failure {
                Text(failure)
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .fieldLineHeight(1.5, size: 13)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
            }
        }
    }

    /// Recomputed rather than stored: a person can add a mail account while
    /// this screen is open, and coming back to a permanently wrong answer is
    /// the kind of small lie the product is built to avoid.
    private var canSendMail: Bool {
        MFMailComposeViewController.canSendMail()
            && WEFeedbackReport.supportAddress != nil
    }

    /// The Share Sheet takes the body as text and the diagnostics as a file
    /// on disk — an in-memory `Data` shares as an unnamed blob.
    private func shareItems() -> [Any]? {
        var items: [Any] = [report.body]
        if let attachment = report.attachment {
            let url = FileManager.default.temporaryDirectory
                .appending(path: WEFeedbackReport.attachmentFilename)
            if (try? attachment.write(to: url, options: .atomic)) != nil {
                items.append(url)
            }
        }
        return items
    }

    private static func summaries(in store: WEDiagnosticsStore) -> [String] {
        store.stored().compactMap { url -> [String]? in
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dictionary = object as? [String: Any]
            else { return nil }
            return WEFeedbackView.summarise(dictionary)
        }
        .flatMap { $0 }
    }

    /// Read back out of the stored JSON rather than kept alongside it, so a
    /// payload that survives a relaunch still describes itself. MetricKit's
    /// JSON keys mirror its class properties.
    private static func summarise(_ payload: [String: Any]) -> [String] {
        var lines: [String] = []
        let counts: [(String, String)] = [
            ("crashDiagnostics", "crash"),
            ("hangDiagnostics", "hang"),
            ("appLaunchDiagnostics", "slow launch"),
            ("cpuExceptionDiagnostics", "CPU exception"),
            ("diskWriteExceptionDiagnostics", "excessive disk write"),
        ]
        for (key, noun) in counts {
            let count = (payload[key] as? [Any])?.count ?? 0
            guard count > 0 else { continue }
            lines.append(count == 1 ? "1 \(noun)" : "\(count) \(noun)s")
        }
        return lines
    }
}

// MARK: - Mail

/// `MFMailComposeViewController` has no SwiftUI equivalent, and the delegate
/// is the only way to learn whether anything was actually sent.
@MainActor
private struct WEMailComposer: UIViewControllerRepresentable {
    enum Result {
        case sent
        case cancelled
        case failed(String)
    }

    let report: WEFeedbackReport
    let recipient: String?
    let completion: (Result) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        if let recipient { controller.setToRecipients([recipient]) }
        controller.setSubject(report.subject)
        controller.setMessageBody(report.body, isHTML: false)

        if let attachment = report.attachment {
            controller.addAttachmentData(
                attachment,
                mimeType: WEFeedbackReport.attachmentMIMEType,
                fileName: WEFeedbackReport.attachmentFilename
            )
        }
        return controller
    }

    func updateUIViewController(
        _ controller: MFMailComposeViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let completion: (Result) -> Void

        init(completion: @escaping (Result) -> Void) {
            self.completion = completion
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)

            if let error {
                WELog.diagnostics.error(
                    "Feedback mail failed: \(error.localizedDescription, privacy: .public)"
                )
                completion(.failed(
                    "That didn't send. \(error.localizedDescription)"
                ))
                return
            }

            switch result {
            case .sent:
                WELog.diagnostics.notice("Feedback sent.")
                completion(.sent)
            case .saved, .cancelled:
                completion(.cancelled)
            case .failed:
                completion(.failed("That didn't send."))
            @unknown default:
                completion(.cancelled)
            }
        }
    }
}

// MARK: - The fallbacks

@MainActor
private struct WEShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ controller: UIActivityViewController,
        context: Context
    ) {}
}

/// The attachment, as text, because "trust me" is not a thing this app says.
@MainActor
private struct WEAttachmentPreview: View {
    let data: Data?

    var body: some View {
        ZStack {
            FieldPalette.bg.ignoresSafeArea()

            ScrollView {
                Text(data.flatMap { String(data: $0, encoding: .utf8) }
                     ?? "Nothing to show.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.fieldInk(.metadataProse))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("field.feedback.attachment.preview")
    }
}
