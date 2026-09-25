//
//  FilterListExporterTests.swift
//  MailwerkTests
//
//  Tests für die Textausgabe einer Filterliste.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct FilterListExporterTests {

    private func entry(_ value: String, _ kind: FilterEntryKind) -> FilterEntryItem {
        FilterEntryItem(
            id: UUID(), value: value, kind: kind, list: .black,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("Eine leere Liste ergibt einen leeren Text")
    func emptyList() {
        #expect(FilterListExporter.text(for: []) == "")
    }

    @Test("Eine Adresse steht unverändert in der Zeile")
    func addressLine() {
        #expect(FilterListExporter.text(for: [entry("anna@firma.de", .address)]) == "anna@firma.de")
    }

    @Test("Eine Domain wird in der Portal-Schreibweise ausgegeben")
    func domainLine() {
        #expect(FilterListExporter.text(for: [entry("firma.de", .domain)]) == "*@firma.de")
    }

    @Test("Adressen stehen vor Domains, beide alphabetisch")
    func sortedOutput() {
        let text = FilterListExporter.text(for: [
            entry("zulu.de", .domain),
            entry("bob@firma.de", .address),
            entry("alpha.de", .domain),
            entry("anna@firma.de", .address)
        ])
        #expect(text == """
            anna@firma.de
            bob@firma.de
            *@alpha.de
            *@zulu.de
            """)
    }

    @Test("Die Datei enthält den Text und trägt den Listennamen")
    func writesFile() throws {
        let url = try FilterListExporter.writeTemporaryFile(
            for: [entry("anna@firma.de", .address), entry("firma.de", .domain)],
            list: .black
        )
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(url.lastPathComponent == "Mailwerk-Blacklist.txt")
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content == "anna@firma.de\n*@firma.de")
    }

    @Test("Ein erneuter Export überschreibt die alte Datei")
    func overwritesFile() throws {
        let first = try FilterListExporter.writeTemporaryFile(
            for: [entry("anna@firma.de", .address)], list: .white
        )
        let second = try FilterListExporter.writeTemporaryFile(
            for: [entry("bob@firma.de", .address)], list: .white
        )
        defer { try? FileManager.default.removeItem(at: second) }

        #expect(first == second)
        #expect(try String(contentsOf: second, encoding: .utf8) == "bob@firma.de")
    }

    @Test("Die Dateinamen unterscheiden die Listen")
    func filenames() {
        #expect(FilterListExporter.filename(for: .white) == "Mailwerk-Whitelist.txt")
        #expect(FilterListExporter.filename(for: .black) == "Mailwerk-Blacklist.txt")
    }
}
