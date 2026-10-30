//
//  FilterListImportTests.swift
//  MailwerkTests
//
//  Zweck: Tests für FilterListImport – Datei lesen (UTF-8 mit BOM,
//  Windows-1252), neue und schon vorhandene Einträge trennen, Format des
//  Exports, Zusammenfassung.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct FilterListImportTests {

    /// Testhilfe: vorhandener Eintrag der Ziel-Liste.
    private func item(_ value: String, _ kind: FilterEntryKind) -> FilterEntryItem {
        FilterEntryItem(id: UUID(), value: value, kind: kind, list: .black, createdAt: Date())
    }

    /// UTF-8 mit vorangestelltem BOM wird ohne BOM gelesen.
    @Test func readsUTF8WithoutBOM() {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("*@firma.de\n".utf8)
        #expect(FilterListImport.text(from: data) == "*@firma.de\n")
    }

    /// Windows-1252 (z. B. „ä“ als 0xE4) ist ebenfalls lesbar.
    @Test func readsWindows1252() {
        let data = Data([0x6D, 0xE4, 0x40, 0x78, 0x2E, 0x64, 0x65]) // „mä@x.de“
        #expect(FilterListImport.text(from: data) == "mä@x.de")
    }

    /// Format des Exports: Adressen und `*@domain` je Zeile; Vorhandenes und Unbrauchbares getrennt.
    @Test func planSeparatesNewPresentAndInvalid() {
        let text = "anna@firma.de\n*@spam.example\n\nunsinn\nANNA@firma.de\n*@alt.example\n"
        let plan = FilterListImport.plan(text: text, existing: [item("alt.example", .domain)])
        #expect(plan.entries == [
            FilterListInputEntry(value: "anna@firma.de", kind: .address),
            FilterListInputEntry(value: "spam.example", kind: .domain)
        ])
        #expect(plan.alreadyPresent == ["alt.example"])
        #expect(plan.invalid == ["unsinn"])
    }

    /// Gleicher Wert, andere Art (Adresse statt Domain) gilt nicht als vorhanden.
    @Test func sameValueOtherKindIsNew() {
        let plan = FilterListImport.plan(text: "*@firma.de", existing: [item("firma.de", .address)])
        #expect(plan.entries == [FilterListInputEntry(value: "firma.de", kind: .domain)])
        #expect(plan.alreadyPresent.isEmpty)
    }

    /// Zusammenfassung nennt Zahlen und abgelehnte Angaben.
    @Test func summaryNamesConflictsAndInvalid() {
        let text = FilterListImport.summary(
            FilterListImport.Outcome(added: 3, alreadyPresent: 1, conflicts: ["a@b.de"], invalid: ["xyz"]),
            otherListName: "Whitelist"
        )
        #expect(text == "3 Einträge übernommen\n1 Eintrag war schon vorhanden\nNicht übernommen, weil bereits auf der Whitelist: a@b.de\nNicht verwertbar: xyz")
        #expect(FilterListImport.summary(FilterListImport.Outcome(), otherListName: "Blacklist")
                == "0 Einträge übernommen")
    }
}
