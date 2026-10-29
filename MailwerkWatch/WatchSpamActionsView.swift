//
//  WatchSpamActionsView.swift
//  MailwerkWatch
//
//  Zweck: „Spam / Vertrauen“ auf der Watch – dieselben Einträge wie in der
//  App: je ein Abschnitt für Adresse, Domain und (nur bei einer Subdomain)
//  Hauptdomain, darin „Blockieren“ und „Vertrauen“. Vor dem Ausführen
//  dieselbe Rückfrage wie in der App.
//
//  Ausführen: sofort auf der Watch (Eintrag in die Listen der Watch, Mail
//  nach „Spam“ bzw. zurück in den Eingang); das iPhone trägt den Wert in
//  die Filterlisten ein und verschiebt die Mail auf dem Server – sofort
//  oder sobald es erreichbar ist. Wurde die Mail verschoben, schließt sich
//  die Mailansicht; sonst bestätigt eine Meldung den Listeneintrag.
//
//  Abgrenzung: Einträge und Texte → SpamMenuChoice; Ausführung →
//  WatchStore (WatchMailbox), WatchConnector.
//
//  Abhängigkeiten: SwiftUI, SpamMenuSection, SpamMenuRequest, SpamMenuTexts,
//  FilterListError, WatchStore, WatchConnector, WatchTransfer.
//

import SwiftUI

/// Spam-Aktionen einer Mail.
struct WatchSpamActionsView: View {
    /// Betroffene Mail.
    let mail: WatchMail
    /// Wird aufgerufen, wenn die Mail dadurch verschoben wurde.
    let onMoved: () -> Void

    /// Speicher der App.
    private let store = WatchStore.shared
    /// Aktion, für die die Rückfrage offen ist.
    @State private var confirming: SpamMenuRequest?
    /// Meldung nach der Aktion; `nil` = keine.
    @State private var resultText: String?

    /// Abschnitte mit „Blockieren“ und „Vertrauen“.
    var body: some View {
        List {
            if let sender = mail.sender {
                ForEach(SpamMenuSection.sections(for: sender)) { section in
                    Section(section.title) {
                        entry(section.request(.block))
                        entry(section.request(.trust))
                    }
                }
            } else {
                Text("Der Absender lässt sich nicht auswerten.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Spam / Vertrauen")
        .alert(
            confirming.map(SpamMenuTexts.confirmationTitle) ?? "",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            presenting: confirming
        ) { request in
            Button(SpamMenuTexts.confirmLabel(request), role: request.kind == .block ? .destructive : nil) {
                run(request)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { request in
            Text(SpamMenuTexts.confirmationMessage(request))
        }
        .alert(
            "Listeneintrag",
            isPresented: Binding(get: { resultText != nil }, set: { if !$0 { resultText = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resultText ?? "")
        }
    }

    /// Ein Eintrag „Blockieren“ bzw. „Vertrauen“.
    ///
    /// - Parameter request: Aktion des Eintrags.
    /// - Returns: Knopf, der die Rückfrage öffnet.
    private func entry(_ request: SpamMenuRequest) -> some View {
        Button(role: request.kind == .block ? .destructive : nil) {
            confirming = request
        } label: {
            Label(SpamMenuTexts.confirmLabel(request), systemImage: SpamMenuTexts.systemImage(request))
        }
    }

    /// Führt die bestätigte Aktion aus.
    ///
    /// Verarbeitung: Steht der Wert schon auf der anderen Liste, erklärt
    /// eine Meldung, was zu tun ist. Wechselt die Mail dadurch zwischen
    /// Eingang und Spam, schließt sich die Mailansicht.
    ///
    /// - Parameter request: Aktion.
    private func run(_ request: SpamMenuRequest) {
        let boxBefore = mail.box
        do {
            try store.perform(.spam(kind: request.kind, entryKind: request.entryKind, value: request.value), on: mail)
        } catch FilterListError.alreadyOnOtherList(let list) {
            resultText = SpamMenuTexts.otherListMessage(request, list: list)
            return
        } catch {
            resultText = error.localizedDescription
            return
        }
        WatchConnector.shared.sendPending()
        if store.mail(id: mail.id)?.box != boxBefore {
            onMoved()
        } else {
            resultText = SpamMenuTexts.resultMessage(request)
        }
    }
}
