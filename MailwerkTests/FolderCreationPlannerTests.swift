//
//  FolderCreationPlannerTests.swift
//  MailwerkTests
//
//  Zweck: Tests für Pfadregel und Namensprüfung beim Anlegen eines Ordners
//  (FolderCreationPlanner).
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für FolderCreationPlanner.
@MainActor
struct FolderCreationPlannerTests {

    // MARK: - Hilfen

    /// Testhilfe: Ordner mit Pfad und Trennzeichen.
    private func folder(_ path: String, delimiter: String? = ".") -> MailFolder {
        MailFolder(
            id: path,
            name: path.components(separatedBy: delimiter ?? ".").last ?? path,
            specialUse: nil,
            hierarchyDelimiter: delimiter
        )
    }

    /// Echte manitu-Liste (2026-09-30): kein Präfix, Trennzeichen „.“.
    private var manitu: FolderListing {
        FolderListing(folders: [
            folder("Test"), folder("Test.Untertest2"), folder("Archive"),
            folder("Sent"), folder("Drafts"), folder("Trash"), folder("Junk"),
            folder("INBOX.Testeingang"), folder("INBOX"),
            folder("Rechnungen M&APw-ller")
        ], namespacePrefix: "")
    }

    /// Server mit Präfix „INBOX.“.
    private var prefixed: FolderListing {
        FolderListing(folders: [
            folder("INBOX"), folder("INBOX.Sent"), folder("INBOX.Projekte")
        ], namespacePrefix: "INBOX.")
    }

    /// Testhilfe: geplanter Pfad für einen Namen.
    private func plan(
        _ name: String,
        under parent: String? = nil,
        in listing: FolderListing? = nil
    ) throws -> String {
        try FolderCreationPlanner.plan(name: name, parentPath: parent, listing: listing ?? manitu)
    }

    /// Testhilfe: Fehler der Planung für einen Namen.
    private func error(
        _ name: String,
        under parent: String? = nil,
        in listing: FolderListing? = nil
    ) -> FolderCreationPlanner.PlanError? {
        do {
            _ = try plan(name, under: parent, in: listing)
            return nil
        } catch let error as FolderCreationPlanner.PlanError {
            return error
        } catch {
            return nil
        }
    }

    // MARK: - Pfadregel (manitu)

    /// manitu: Ordner auf oberster Ebene ohne Präfix.
    @Test func topLevelOnManitu() throws {
        #expect(try plan("Projekte") == "Projekte")
    }

    /// manitu: Unterordner des Posteingangs mit „INBOX.“.
    @Test func subfolderOfInboxOnManitu() throws {
        #expect(try plan("Kunden", under: "INBOX") == "INBOX.Kunden")
    }

    /// Unterordner eines gewöhnlichen Ordners.
    @Test func subfolderOfRegularFolder() throws {
        #expect(try plan("Neu", under: "Test") == "Test.Neu")
        #expect(try plan("Tief", under: "Test.Untertest2") == "Test.Untertest2.Tief")
    }

    /// Unterordner eines Sonderordners.
    @Test func subfolderOfSpecialFolder() throws {
        #expect(try plan("2025", under: "Archive") == "Archive.2025")
    }

    /// Der Name wird gekürzt und in modified UTF-7 kodiert.
    @Test func nameIsEncodedAndTrimmed() throws {
        #expect(try plan("  Größe  ") == "Gr&APYA3w-e")
        #expect(try plan("Haus & Hof", under: "INBOX") == "INBOX.Haus &- Hof")
        #expect(try plan("Jahr", under: "Rechnungen M&APw-ller") == "Rechnungen M&APw-ller.Jahr")
    }

    // MARK: - Pfadregel (Präfix „INBOX.“)

    /// Mit Namespace-Präfix liegt ein neuer Ordner unter dem Präfix.
    @Test func topLevelWithPrefix() throws {
        #expect(try plan("Kunden", in: prefixed) == "INBOX.Kunden")
        #expect(try plan("2026", under: "INBOX.Projekte", in: prefixed) == "INBOX.Projekte.2026")
    }

    /// Mit Präfix sind Unterordner des Posteingangs nicht möglich.
    @Test func noSubfolderOfInboxWithPrefix() {
        #expect(error("Kunden", under: "INBOX", in: prefixed) == .subfoldersNotSupported)
    }

    /// Ohne Trennzeichen sind keine Unterordner möglich.
    @Test func noSubfoldersWithoutDelimiter() {
        let flat = FolderListing(folders: [folder("INBOX", delimiter: nil)], namespacePrefix: nil)
        #expect(error("Neu", under: "INBOX", in: flat) == .subfoldersNotSupported)
    }

    // MARK: - Namensprüfung

    /// Ein leerer Name wird abgelehnt.
    @Test func emptyNameIsRejected() {
        #expect(error("") == .emptyName)
        #expect(error("   ") == .emptyName)
    }

    /// Ein Name mit Trennzeichen wird abgelehnt.
    @Test func delimiterIsRejected() {
        #expect(error("v1.2") == .containsDelimiter("."))
    }

    /// Platzhalter und Steuerzeichen werden abgelehnt.
    @Test func wildcardsAndControlCharactersAreRejected() {
        #expect(error("Alle*") == .invalidCharacters)
        #expect(error("50%") == .invalidCharacters)
        #expect(error("Zeile\u{7}") == .invalidCharacters)
    }

    /// „INBOX“ ist auf oberster Ebene reserviert.
    @Test func inboxNameIsReservedOnTopLevel() {
        #expect(error("inbox") == .reservedName)
    }

    // MARK: - Doppelte Namen

    /// Ein gleichnamiger Ordner auf derselben Ebene wird abgelehnt, ohne Groß-/Kleinschreibung.
    @Test func duplicateOnSameLevelIsRejectedCaseInsensitive() {
        #expect(error("test") == .alreadyExists("Test"))
        #expect(error("Testeingang", under: "INBOX") == .alreadyExists("Testeingang"))
        #expect(error("rechnungen müller") == .alreadyExists("Rechnungen Müller"))
    }

    /// Derselbe Name auf einer anderen Ebene ist erlaubt.
    @Test func sameNameOnOtherLevelIsAllowed() throws {
        #expect(try plan("Untertest2") == "Untertest2")
        #expect(try plan("Test", under: "INBOX") == "INBOX.Test")
    }
}
