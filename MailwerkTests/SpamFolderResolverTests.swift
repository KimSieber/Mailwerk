//
//  SpamFolderResolverTests.swift
//  MailwerkTests
//
//  Zweck: Tests für das Auffinden des Spam-Ordners eines Postfachs
//  (SpamFolderResolver).
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für SpamFolderResolver.
@MainActor
struct SpamFolderResolverTests {

    // MARK: - Hilfen

    /// Testhilfe: Ordner mit Pfad und Rolle.
    private func folder(
        _ path: String,
        specialUse: MailFolder.SpecialUse? = nil,
        delimiter: String? = "."
    ) -> MailFolder {
        let name = path.components(separatedBy: delimiter ?? ".").last ?? path
        return MailFolder(
            id: path,
            name: name,
            specialUse: specialUse,
            hierarchyDelimiter: delimiter
        )
    }

    /// Testhilfe: Ergebnis der Suche für eine Ordnerliste.
    private func resolve(
        _ folders: [MailFolder],
        delimiter: String? = ".",
        configured: String? = nil
    ) -> SpamFolderResolver.Resolution {
        SpamFolderResolver.resolve(
            folders: folders, delimiter: delimiter, configured: configured
        )
    }

    // MARK: - Gemerkter Ordner

    /// Der gemerkte Ordner wird bevorzugt, auch gegen SPECIAL-USE.
    @Test("Der gemerkte Ordner wird bevorzugt, auch gegen SPECIAL-USE")
    func prefersConfiguredFolder() {
        let folders = [folder("Spam"), folder("Junk", specialUse: .junk)]
        #expect(resolve(folders, configured: "Spam") == .found("Spam"))
    }

    /// Ein gemerkter Ordner, den es nicht mehr gibt, wird verworfen.
    @Test("Ein gemerkter Ordner, den es nicht mehr gibt, wird verworfen")
    func ignoresVanishedConfiguredFolder() {
        let folders = [folder("Junk", specialUse: .junk)]
        #expect(resolve(folders, configured: "Alt-Spam") == .found("Junk"))
    }

    /// Ohne passenden Ordner führt ein verwaister Merkwert zum Vorschlag.
    @Test("Ohne passenden Ordner führt ein verwaister Merkwert zum Vorschlag")
    func vanishedConfiguredWithoutAlternative() {
        #expect(resolve([folder("Sent", specialUse: .sent)], configured: "Alt-Spam")
                == .missing(proposal: "Junk"))
    }

    // MARK: - Abkürzung über die gecachte Ordnerliste

    /// Steht der gemerkte Ordner in der Liste, wird er geliefert (auch bei abweichender Schreibweise).
    @Test("knownFolder liefert den gemerkten Ordner aus der Liste")
    func knownFolderFindsConfigured() {
        let folders = [folder("INBOX"), folder("INBOX.Spam")]
        #expect(SpamFolderResolver.knownFolder(in: folders, configured: "INBOX.Spam") == "INBOX.Spam")
        #expect(SpamFolderResolver.knownFolder(in: folders, configured: "inbox.spam") == "INBOX.Spam")
    }

    /// Fehlt der gemerkte Ordner oder ist keiner gemerkt, gibt es keine Abkürzung.
    @Test("knownFolder liefert nil ohne Treffer oder ohne Merkwert")
    func knownFolderWithoutMatch() {
        let folders = [folder("Junk", specialUse: .junk)]
        #expect(SpamFolderResolver.knownFolder(in: folders, configured: "Alt-Spam") == nil)
        #expect(SpamFolderResolver.knownFolder(in: folders, configured: nil) == nil)
        #expect(SpamFolderResolver.knownFolder(in: folders, configured: "") == nil)
    }

    // MARK: - SPECIAL-USE

    /// SPECIAL-USE \\Junk gewinnt gegen einen namensgleichen Treffer.
    @Test("SPECIAL-USE \\Junk gewinnt gegen einen namensgleichen Treffer")
    func prefersSpecialUse() {
        let folders = [folder("Spam"), folder("Unerwünscht", specialUse: .junk)]
        #expect(resolve(folders) == .found("Unerwünscht"))
    }

    /// Andere Spezialordner werden nicht verwechselt.
    @Test("Andere Spezialordner werden nicht verwechselt")
    func ignoresOtherSpecialUse() {
        let folders = [folder("Trash", specialUse: .trash), folder("Sent", specialUse: .sent)]
        #expect(resolve(folders) == .missing(proposal: "Junk"))
    }

    // MARK: - Namenssuche

    /// Gebräuchliche Namen werden erkannt, unabhängig von Groß-/Kleinschreibung.
    @Test("Gebräuchliche Namen werden erkannt, unabhängig von Groß-/Kleinschreibung",
          arguments: ["Junk", "junk", "SPAM", "Spam", "Junk E-Mail", "Junk-E-Mail", "Bulk Mail"])
    func findsByName(name: String) {
        #expect(resolve([folder("Sent", specialUse: .sent), folder(name)]) == .found(name))
    }

    /// Auch ein Unterordner der INBOX wird gefunden.
    @Test("Auch ein Unterordner der INBOX wird gefunden")
    func findsNestedFolder() {
        #expect(resolve([folder("INBOX.Spam")]) == .found("INBOX.Spam"))
    }

    /// Bei mehreren Namenstreffern gewinnt die Reihenfolge der Kandidaten.
    @Test("Bei mehreren Namenstreffern gewinnt die Reihenfolge der Kandidaten")
    func candidateOrderWins() {
        #expect(resolve([folder("Spam"), folder("Junk")]) == .found("Junk"))
    }

    /// Bei gleichem Namen auf mehreren Ebenen gewinnt der oberste Ordner.
    @Test("Bei gleichem Namen auf mehreren Ebenen gewinnt der oberste Ordner")
    func prefersShallowFolder() {
        #expect(resolve([folder("Archiv.2024.Spam"), folder("Spam")]) == .found("Spam"))
    }

    /// Ähnliche Namen zählen nicht.
    @Test("Ähnliche Namen zählen nicht",
          arguments: ["Spamverdacht", "Nicht-Junk", "Junkyard", "Antispam"])
    func rejectsSimilarNames(name: String) {
        #expect(resolve([folder(name)]) == .missing(proposal: "Junk"))
    }

    // MARK: - Vorschlag zum Anlegen

    /// Ohne Treffer wird ein Ordner vorgeschlagen, aber nicht angelegt.
    @Test("Ohne Treffer wird ein Ordner vorgeschlagen, aber nicht angelegt")
    func proposesTopLevelFolder() {
        #expect(resolve([folder("Sent", specialUse: .sent)]) == .missing(proposal: "Junk"))
    }

    /// Liegen alle Ordner unter der INBOX, folgt der Vorschlag dieser Hierarchie.
    @Test("Liegen alle Ordner unter der INBOX, folgt der Vorschlag dieser Hierarchie")
    func proposesNestedFolderWhenServerNests() {
        let folders = [folder("INBOX.Sent", specialUse: .sent), folder("INBOX.Trash", specialUse: .trash)]
        #expect(resolve(folders) == .missing(proposal: "INBOX.Junk"))
    }

    /// Das Trennzeichen des Servers wird übernommen.
    @Test("Das Trennzeichen des Servers wird übernommen")
    func proposalUsesServerDelimiter() {
        let folders = [folder("INBOX/Sent", specialUse: .sent, delimiter: "/")]
        #expect(resolve(folders, delimiter: "/") == .missing(proposal: "INBOX/Junk"))
    }

    /// Ohne Ordnerliste bleibt es beim einfachen Vorschlag.
    @Test("Ohne Ordnerliste bleibt es beim einfachen Vorschlag")
    func proposalWithoutFolders() {
        #expect(resolve([], delimiter: nil) == .missing(proposal: "Junk"))
    }
}
