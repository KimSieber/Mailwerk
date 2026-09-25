//
//  SpamFolderResolverTests.swift
//  MailwerkTests
//
//  Tests für das Auffinden des Spam-Ordners eines Postfachs.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct SpamFolderResolverTests {

    // MARK: - Hilfen

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

    @Test("Der gemerkte Ordner wird bevorzugt, auch gegen SPECIAL-USE")
    func prefersConfiguredFolder() {
        let folders = [folder("Spam"), folder("Junk", specialUse: .junk)]
        #expect(resolve(folders, configured: "Spam") == .found("Spam"))
    }

    @Test("Ein gemerkter Ordner, den es nicht mehr gibt, wird verworfen")
    func ignoresVanishedConfiguredFolder() {
        let folders = [folder("Junk", specialUse: .junk)]
        #expect(resolve(folders, configured: "Alt-Spam") == .found("Junk"))
    }

    @Test("Ohne passenden Ordner führt ein verwaister Merkwert zum Vorschlag")
    func vanishedConfiguredWithoutAlternative() {
        #expect(resolve([folder("Sent", specialUse: .sent)], configured: "Alt-Spam")
                == .missing(proposal: "Junk"))
    }

    // MARK: - SPECIAL-USE

    @Test("SPECIAL-USE \\Junk gewinnt gegen einen namensgleichen Treffer")
    func prefersSpecialUse() {
        let folders = [folder("Spam"), folder("Unerwünscht", specialUse: .junk)]
        #expect(resolve(folders) == .found("Unerwünscht"))
    }

    @Test("Andere Spezialordner werden nicht verwechselt")
    func ignoresOtherSpecialUse() {
        let folders = [folder("Trash", specialUse: .trash), folder("Sent", specialUse: .sent)]
        #expect(resolve(folders) == .missing(proposal: "Junk"))
    }

    // MARK: - Namenssuche

    @Test("Gebräuchliche Namen werden erkannt, unabhängig von Groß-/Kleinschreibung",
          arguments: ["Junk", "junk", "SPAM", "Spam", "Junk E-Mail", "Junk-E-Mail", "Bulk Mail"])
    func findsByName(name: String) {
        #expect(resolve([folder("Sent", specialUse: .sent), folder(name)]) == .found(name))
    }

    @Test("Auch ein Unterordner der INBOX wird gefunden")
    func findsNestedFolder() {
        #expect(resolve([folder("INBOX.Spam")]) == .found("INBOX.Spam"))
    }

    @Test("Bei mehreren Namenstreffern gewinnt die Reihenfolge der Kandidaten")
    func candidateOrderWins() {
        #expect(resolve([folder("Spam"), folder("Junk")]) == .found("Junk"))
    }

    @Test("Bei gleichem Namen auf mehreren Ebenen gewinnt der oberste Ordner")
    func prefersShallowFolder() {
        #expect(resolve([folder("Archiv.2024.Spam"), folder("Spam")]) == .found("Spam"))
    }

    @Test("Ähnliche Namen zählen nicht",
          arguments: ["Spamverdacht", "Nicht-Junk", "Junkyard", "Antispam"])
    func rejectsSimilarNames(name: String) {
        #expect(resolve([folder(name)]) == .missing(proposal: "Junk"))
    }

    // MARK: - Vorschlag zum Anlegen

    @Test("Ohne Treffer wird ein Ordner vorgeschlagen, aber nicht angelegt")
    func proposesTopLevelFolder() {
        #expect(resolve([folder("Sent", specialUse: .sent)]) == .missing(proposal: "Junk"))
    }

    @Test("Liegen alle Ordner unter der INBOX, folgt der Vorschlag dieser Hierarchie")
    func proposesNestedFolderWhenServerNests() {
        let folders = [folder("INBOX.Sent", specialUse: .sent), folder("INBOX.Trash", specialUse: .trash)]
        #expect(resolve(folders) == .missing(proposal: "INBOX.Junk"))
    }

    @Test("Das Trennzeichen des Servers wird übernommen")
    func proposalUsesServerDelimiter() {
        let folders = [folder("INBOX/Sent", specialUse: .sent, delimiter: "/")]
        #expect(resolve(folders, delimiter: "/") == .missing(proposal: "INBOX/Junk"))
    }

    @Test("Ohne Ordnerliste bleibt es beim einfachen Vorschlag")
    func proposalWithoutFolders() {
        #expect(resolve([], delimiter: nil) == .missing(proposal: "Junk"))
    }
}
