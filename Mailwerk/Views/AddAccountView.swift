//
//  AddAccountView.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 18.09.2026
//  Geändert: 30.10.2026
//
//  Zweck: Formular zum Einrichten eines Postfachs. Zuerst wählt der Nutzer
//  die Art:
//  - „Microsoft (Outlook.com, Hotmail, Live)“: nur Bezeichnung,
//    Absendername, E-Mail-Adresse, Benutzername (leer = E-Mail-Adresse)
//    und Farbe; die Server sind fest
//    hinterlegt, ein Passwort gibt es nicht. „Bei Microsoft anmelden“
//    öffnet die Anmeldeseite von Microsoft, prüft danach IMAP und SMTP und
//    speichert das Postfach von selbst – das Formular schließt sich.
//  - „Anderer Anbieter (IMAP/SMTP)“: das bisherige Formular mit
//    Benutzername, Passwort, IMAP- und SMTP-Server, Kopie in „Gesendet“,
//    Farbe und Verbindungstest; gespeichert wird mit „Speichern“.
//
//  Jede Zeile zeigt ihre Beschriftung und ein Beispiel
//  (LabeledInputField). Scheitert das Speichern oder die Anmeldung,
//  bleibt das Formular mit allen Eingaben offen und eine Meldung erklärt
//  den Grund.
//
//  Mac: feste Kopfleiste oben (✕ Abbrechen, bei IMAP/SMTP
//  ✓ Speichern) statt Symbolleiste; das Formular im gruppierten Stil
//  (Karten, Beschriftung links) scrollt darunter vollständig.
//
//  Abgrenzung: Eingabeprüfung, Verbindungstest, Anmeldung und Aufbau des
//  Postfachs → AddAccountViewModel; Bearbeiten → EditAccountView.
//
//  Abhängigkeiten: SwiftUI, AddAccountViewModel, AccountStore, Dialogs,
//  LabeledInputField, PlatformInputModifiers (Eingabearten der Felder),
//  ColorPickerGrid, OAuthProvider, OAuthSignInState, AppTheme (getönte
//  Fläche, Abschnitte als Karten), SheetHeaderBar, PlatformSheetSize.
//

import SwiftUI

/// Formular „Postfach hinzufügen“.
struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    /// Eingaben, Verbindungstest und Anmeldung.
    @State private var viewModel = AddAccountViewModel()
    /// Einziger Meldungskanal der Ansicht.
    @State private var activeAlert: AlertItem?
    /// Quelle für Postfächer; hier wird das neue Postfach eingetragen.
    let accountStore: AccountStore

    /// Formular: Art, dann je nach Art die passenden Abschnitte.
    var body: some View {
        NavigationStack {
            Form {
                kindSection
                if let provider = viewModel.provider {
                    oauthSections(provider)
                } else {
                    imapSections
                }
            }
            .macGroupedForm()
            .appBackground()
            .navigationTitle("Postfach hinzufügen")
            .macSheetHeader("Postfach hinzufügen") {
                HeaderCircleButton.cancel { dismiss() }
            } trailing: {
                if viewModel.provider == nil {
                    HeaderCircleButton.confirm("Speichern", isEnabled: viewModel.isValid) { save() }
                }
            }
            #if !os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                if viewModel.provider == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Speichern") { save() }
                            .disabled(!viewModel.isValid)
                    }
                }
            }
            #endif
        }
        .alertItem($activeAlert)
        .macSheetFrame(.form)
    }

    // MARK: - Art

    /// Wahl der Art: Microsoft oder anderer Anbieter.
    private var kindSection: some View {
        Section {
            Picker("Art des Postfachs", selection: $viewModel.kind) {
                Text(OAuthProvider.microsoft.accountKindTitle)
                    .tag(AddAccountViewModel.Kind.oauth(.microsoft))
                Text("Anderer Anbieter (IMAP/SMTP)")
                    .tag(AddAccountViewModel.Kind.imap)
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .disabled(viewModel.signInProgress != nil)
        } header: {
            Text("Art des Postfachs")
        }
        .cardRowBackground()
    }

    // MARK: - Anbieter mit Anmeldung (Microsoft)

    /// Abschnitte für ein Postfach mit Anmeldung beim Anbieter.
    ///
    /// - Parameter provider: Anbieter.
    /// - Returns: Konto, Farbe und Anmeldung.
    @ViewBuilder
    private func oauthSections(_ provider: OAuthProvider) -> some View {
        Section {
            LabeledInputField(label: "Bezeichnung", example: "z. B. Outlook",
                              text: $viewModel.displayName)
            LabeledInputField(label: "Absendername", example: "z. B. Max Müller",
                              text: $viewModel.senderName)
                .textContentType(.name)
            LabeledInputField(label: "E-Mail-Adresse", example: "z. B. max.mueller@outlook.com",
                              text: $viewModel.emailAddress)
                .emailInput()
            LabeledInputField(label: "Benutzername", example: "leer = E-Mail-Adresse",
                              text: $viewModel.username)
                .emailInput()
        } header: {
            Text("Konto")
        } footer: {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("Die Bezeichnung dient nur zur Anzeige in Mailwerk, der Absendername erscheint beim Empfänger vor der Adresse. Den Benutzernamen nur eintragen, wenn du dich bei \(provider.name) mit einer anderen Adresse anmeldest als mit der E-Mail-Adresse.")
                if !viewModel.emailAddress.isEmpty && !viewModel.hasValidEmailAddress {
                    Text("Die E-Mail-Adresse ist ungültig.")
                        .foregroundStyle(.red)
                }
            }
        }
        .disabled(viewModel.signInProgress != nil)
        .cardRowBackground()

        colorSection

        oauthSignInSection(provider)
    }

    /// Abschnitt „Anmeldung“ bei einem Anbieter: Knopf mit Fortschritt und
    /// ggf. Fehlermeldung.
    ///
    /// - Parameter provider: Anbieter.
    /// - Returns: Der Abschnitt.
    private func oauthSignInSection(_ provider: OAuthProvider) -> some View {
        Section {
            Button {
                Task { await signIn() }
            } label: {
                if let progress = viewModel.signInProgress {
                    HStack(spacing: AppSpacing.regular) {
                        ProgressView()
                        Text(progress)
                    }
                } else {
                    Label("Bei \(provider.name) anmelden", systemImage: "person.badge.key")
                }
            }
            .disabled(!viewModel.isReadyForSignIn || viewModel.signInProgress != nil
                      || !OAuthSignInState.shared.canSignIn)

            if case .failure(let message) = viewModel.testResult {
                Label(message, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Anmeldung")
        } footer: {
            Text("Es öffnet sich die Anmeldeseite von \(provider.name). Mailwerk erhält dabei kein Passwort, nur die Freigabe für Abruf und Versand. Danach wird die Verbindung geprüft und das Postfach gespeichert. IMAP muss im Webmail eingeschaltet sein (Outlook.com: Einstellungen → E-Mail → Weiterleitung und IMAP).")
        }
        .cardRowBackground()
    }

    // MARK: - Anderer Anbieter (IMAP/SMTP)

    /// Abschnitte für ein Postfach mit Passwort: Konto, IMAP, SMTP, Farbe,
    /// Verbindungstest.
    @ViewBuilder
    private var imapSections: some View {
        Section {
            LabeledInputField(label: "Bezeichnung", example: "z. B. Privat",
                              text: $viewModel.displayName)
            LabeledInputField(label: "Absendername", example: "z. B. Max Müller",
                              text: $viewModel.senderName)
                .textContentType(.name)
            LabeledInputField(label: "E-Mail-Adresse", example: "z. B. max.mueller@mail.org",
                              text: $viewModel.emailAddress)
                .emailInput()
            LabeledInputField(label: "Benutzername", example: "leer = E-Mail-Adresse",
                              text: $viewModel.username)
                .plainTextInput()
            LabeledInputField(label: "Passwort", example: "erforderlich",
                              text: $viewModel.password, isSecure: true)
        } header: {
            Text("Konto")
        } footer: {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("Die Bezeichnung dient nur zur Anzeige in Mailwerk, der Absendername erscheint beim Empfänger vor der Adresse. Den Benutzernamen nur eintragen, wenn sich der Anbieter nicht mit der E-Mail-Adresse anmeldet.")
                if !viewModel.emailAddress.isEmpty && !viewModel.hasValidEmailAddress {
                    Text("Die E-Mail-Adresse ist ungültig.")
                        .foregroundStyle(.red)
                }
            }
        }
        .cardRowBackground()

        Section("IMAP (Empfang)") {
            LabeledInputField(label: "Host", example: "z. B. imap.mail.org",
                              text: $viewModel.imapHost)
                .plainTextInput()
            LabeledInputField(label: "Port", example: "z. B. 993",
                              text: $viewModel.imapPort)
                .numberInput()
        }
        .cardRowBackground()

        Section {
            LabeledInputField(label: "Host", example: "z. B. smtp.mail.org",
                              text: $viewModel.smtpHost)
                .plainTextInput()
            LabeledInputField(label: "Port", example: "z. B. 587",
                              text: $viewModel.smtpPort)
                .numberInput()
            Toggle("Kopie in „Gesendet“ ablegen", isOn: $viewModel.savesSentCopy)
                // Einzelner Schalter: auf dem Mac als Schalter statt Häkchen.
                .toggleStyle(.switch)
        } header: {
            Text("SMTP (Versand)")
        } footer: {
            Text("Ausschalten, wenn der Anbieter gesendete Mails selbst in „Gesendet“ ablegt (z. B. Gmail) – sonst erscheinen sie dort doppelt.")
        }
        .cardRowBackground()

        colorSection

        Section {
            Button {
                Task { await viewModel.testConnection() }
            } label: {
                if viewModel.isTesting {
                    ProgressView()
                } else {
                    Text("Verbindung testen")
                }
            }
            .disabled(!viewModel.isValid || viewModel.isTesting)

            if let result = viewModel.testResult {
                switch result {
                case .success:
                    Label("Verbindung erfolgreich", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failure(let message):
                    Label(message, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .cardRowBackground()
    }

    /// Wahl der Farbe des Postfachs (beide Arten).
    private var colorSection: some View {
        Section("Farbe") {
            ColorPickerGrid(selection: $viewModel.selectedColor)
        }
        .disabled(viewModel.signInProgress != nil)
        .cardRowBackground()
    }

    // MARK: - Aktionen

    /// Legt das Postfach an (Art IMAP/SMTP) und schließt das Formular.
    ///
    /// Verarbeitung: Scheitert das Speichern (z. B. Schlüsselbund), bleibt
    /// das Formular offen, damit keine Eingaben verloren gehen.
    private func save() {
        let account = viewModel.makeAccount()
        do {
            try accountStore.addAccount(account, password: viewModel.password)
            dismiss()
        } catch {
            activeAlert = .failure("Speichern fehlgeschlagen", error)
        }
    }

    /// Meldet beim Anbieter an und schließt das Formular, sobald das
    /// Postfach gespeichert ist.
    ///
    /// Verarbeitung: Fehler zeigt das Formular selbst unter dem Knopf an;
    /// es bleibt dann offen.
    private func signIn() async {
        if await viewModel.signInAndSave(accountStore: accountStore) {
            dismiss()
        }
    }
}
