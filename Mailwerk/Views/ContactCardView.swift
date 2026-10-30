//
//  ContactCardView.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 16.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Die Apple-Kontaktkarte zu einer Person aus dem Mailkopf
//  („Kontaktkarte anzeigen“).
//  - Steht die Adresse im Adressbuch, erscheint dieser Kontakt.
//  - Sonst (oder ohne Zugriff auf die Kontakte) eine Karte mit Name und
//    Adresse; auf iPhone/iPad bietet sie „Neuen Kontakt erstellen“ und
//    „Zu bestehendem Kontakt hinzufügen“ an.
//  Auf dem Mac zeigt die Systemkarte nur an; Anlegen geht dort über die
//  App Kontakte.
//
//  Abgrenzung: Auslöser ist das Menü einer Person (MessageDetailHeader);
//  das Blatt öffnet MessageDetailView.
//
//  Abhängigkeiten: SwiftUI, Contacts, ContactsUI, UIKit (iOS) bzw. AppKit
//  (macOS), HeaderPerson.
//

import Contacts
import ContactsUI
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Blatt mit der Kontaktkarte einer Person.
struct ContactCardView: View {
    /// Person aus dem Mailkopf.
    let person: HeaderPerson

    /// Schließt das Blatt.
    @Environment(\.dismiss) private var dismiss

    /// Systemkarte; auf dem Mac mit eigener Kopfleiste zum Schließen.
    var body: some View {
        let lookup = ContactCardLookup.contact(for: person)
        #if os(iOS)
        ContactCardController(contact: lookup.contact, isKnown: lookup.isKnown, onClose: { dismiss() })
            .ignoresSafeArea()
        #else
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(AppSpacing.medium)
            Divider()
            ContactCardController(contact: lookup.contact)
        }
        .frame(minWidth: 360, minHeight: 420)
        #endif
    }
}

// MARK: - Kontakt suchen

/// Sucht den Kontakt zu einer Adresse bzw. legt einen ungespeicherten an.
enum ContactCardLookup {
    /// Kontakt aus dem Adressbuch oder ungespeicherter Kontakt.
    ///
    /// Verarbeitung: Sucht im Adressbuch nach der Adresse (mit den Feldern,
    /// die die Systemkarte braucht). Ohne Treffer oder ohne Zugriff entsteht
    /// ein ungespeicherter Kontakt mit Name (in Vor- und Nachname zerlegt)
    /// und Adresse.
    ///
    /// - Parameter person: Person aus dem Mailkopf.
    /// - Returns: Kontakt und ob er im Adressbuch steht.
    static func contact(for person: HeaderPerson) -> (contact: CNContact, isKnown: Bool) {
        // Ohne Zugriff auf die Kontakte scheitert die Suche still – dann
        // gilt die Adresse als unbekannt.
        let keys = [CNContactViewController.descriptorForRequiredKeys()]
        let predicate = CNContact.predicateForContacts(matchingEmailAddress: person.address)
        if let found = try? CNContactStore().unifiedContacts(matching: predicate, keysToFetch: keys).first {
            return (found, true)
        }
        let unknown = CNMutableContact()
        if let name = person.name {
            let parts = name.split(separator: " ")
            if parts.count > 1 {
                unknown.givenName = parts.dropLast().joined(separator: " ")
                unknown.familyName = String(parts.last ?? "")
            } else {
                unknown.givenName = name
            }
        }
        unknown.emailAddresses = [CNLabeledValue(label: CNLabelOther, value: person.address as NSString)]
        return (unknown, false)
    }
}

// MARK: - Systemkarte

#if os(iOS)
/// Systemkarte (`CNContactViewController`) in einer Navigation, damit
/// „Neuer Kontakt“ und „Zu Kontakt hinzufügen“ arbeiten können.
struct ContactCardController: UIViewControllerRepresentable {
    /// Gezeigter Kontakt.
    let contact: CNContact
    /// `true`, wenn er im Adressbuch steht.
    let isKnown: Bool
    /// Schließt das Blatt.
    let onClose: () -> Void

    /// Legt Navigation und Karte an.
    ///
    /// - Parameter context: Kontext von SwiftUI.
    /// - Returns: Navigation mit der Karte.
    func makeUIViewController(context: Context) -> UINavigationController {
        let card: CNContactViewController
        if isKnown {
            card = CNContactViewController(for: contact)
        } else {
            card = CNContactViewController(forUnknownContact: contact)
            card.contactStore = CNContactStore()
        }
        card.allowsActions = true
        let close = onClose
        card.navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { _ in close() }
        )
        return UINavigationController(rootViewController: card)
    }

    /// Nichts zu aktualisieren – die Karte ändert sich nicht.
    ///
    /// - Parameters:
    ///   - controller: Navigation mit der Karte.
    ///   - context: Kontext von SwiftUI.
    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}
#else
/// Systemkarte (`CNContactViewController`) zum Ansehen.
struct ContactCardController: NSViewControllerRepresentable {
    /// Gezeigter Kontakt.
    let contact: CNContact

    /// Legt die Karte an.
    ///
    /// - Parameter context: Kontext von SwiftUI.
    /// - Returns: Die Karte.
    func makeNSViewController(context: Context) -> CNContactViewController {
        let card = CNContactViewController()
        card.contact = contact
        return card
    }

    /// Nichts zu aktualisieren – die Karte ändert sich nicht.
    ///
    /// - Parameters:
    ///   - controller: Die Karte.
    ///   - context: Kontext von SwiftUI.
    func updateNSViewController(_ controller: CNContactViewController, context: Context) {}
}
#endif
