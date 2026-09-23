
//
//  ContactSuggestion.swift
//  Mailwerk
//
//  Created by Kim Sieber on 23.09.26.
//


//
//  ContactSuggestionService.swift
//  Mailwerk
//
//  Adressvorschläge aus den Systemkontakten.
//
//  Datenschutz: Die Berechtigung wird erst beim ersten Antippen eines
//  Adressfelds angefragt. Kontakte werden ausschließlich live gelesen,
//  niemals gespeichert oder übertragen. Ohne Berechtigung bleibt das
//  Adressfeld voll benutzbar, nur ohne Vorschläge.
//
//  Die Abfrage läuft in einer abgetrennten Aufgabe, damit die Eingabe
//  auch bei sehr vielen Kontakten flüssig bleibt.
//

import Foundation
import Contacts
import SwiftMail

/// Ein Vorschlag für ein Adressfeld.
struct ContactSuggestion: Identifiable, Hashable {
    let name: String?
    let address: String

    var id: String { "\(name ?? "")|\(address.lowercased())" }
    var mailAddress: MailAddress { MailAddress(name: name, address: address) }
}

final class ContactSuggestionService {
    static let shared = ContactSuggestionService()

    /// Ab dieser Länge wird gesucht – kürzere Eingaben liefern zu viele Treffer.
    static let minimumQueryLength = 2

    private init() {}

    var authorizationStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    /// true, wenn gesucht werden darf – auch bei eingeschränktem Zugriff
    /// (dann sind nur die freigegebenen Kontakte sichtbar).
    var isAccessAllowed: Bool {
        switch authorizationStatus {
        case .authorized, .limited: return true
        default: return false
        }
    }

    /// Fragt die Berechtigung an, falls noch nicht entschieden.
    @discardableResult
    func requestAccessIfNeeded() async -> CNAuthorizationStatus {
        guard authorizationStatus == .notDetermined else { return authorizationStatus }
        _ = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            CNContactStore().requestAccess(for: .contacts) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
        return authorizationStatus
    }

    /// Sucht passende Kontakte zu einer Eingabe.
    func suggestions(matching query: String, limit: Int = 6) async -> [ContactSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumQueryLength, isAccessAllowed else { return [] }

        let rows = await Task.detached(priority: .userInitiated) {
            Self.search(trimmed, limit: limit)
        }.value

        return rows.map {
            ContactSuggestion(name: $0.name.isEmpty ? nil : $0.name, address: $0.address)
        }
    }

    // MARK: - Suche (außerhalb des Haupt-Threads)

    private nonisolated static func search(
        _ query: String,
        limit: Int
    ) -> [(name: String, address: String)] {
        // Der Formatter braucht mehr Felder als nur Vor- und Nachname
        // (Namenszusätze, Sortiernamen …). Werden sie nicht angefordert,
        // wirft der Zugriff CNPropertyNotFetchedException und beendet die App.
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]
        let store = CNContactStore()
        var contacts: [CNContact] = []

        // Treffer über den Namen
        let byName = try? store.unifiedContacts(
            matching: CNContact.predicateForContacts(matchingName: query),
            keysToFetch: keys
        )
        contacts += byName ?? []

        // Zusätzlich über die Adresse, sobald ein @ getippt wurde
        if query.contains("@") {
            let byMail = try? store.unifiedContacts(
                matching: CNContact.predicateForContacts(matchingEmailAddress: query),
                keysToFetch: keys
            )
            contacts += byMail ?? []
        }

        let needle = query.lowercased()
        var seen = Set<String>()
        var result: [(name: String, address: String)] = []

        for contact in contacts {
            let name = displayName(of: contact)
            for entry in contact.emailAddresses {
                let address = (entry.value as String)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard address.isValidEmail() else { continue }
                guard name.lowercased().contains(needle)
                    || address.lowercased().contains(needle) else { continue }
                guard seen.insert(address.lowercased()).inserted else { continue }
                result.append((name: name, address: address))
            }
        }

        // Treffer am Wortanfang zuerst, danach alphabetisch
        return Array(
            result.sorted { lhs, rhs in
                let lhsPrefix = startsWith(needle, lhs)
                let rhsPrefix = startsWith(needle, rhs)
                if lhsPrefix != rhsPrefix { return lhsPrefix }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(limit)
        )
    }

    private nonisolated static func startsWith(
        _ needle: String,
        _ row: (name: String, address: String)
    ) -> Bool {
        row.name.lowercased().hasPrefix(needle) || row.address.lowercased().hasPrefix(needle)
    }

    private nonisolated static func displayName(of contact: CNContact) -> String {
        let name = CNContactFormatter.string(from: contact, style: .fullName)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? contact.organizationName : name
    }
}
