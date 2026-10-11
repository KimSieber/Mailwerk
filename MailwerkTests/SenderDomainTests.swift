//
//  SenderDomainTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Domain-Regeln der Absenderlogos (SenderDomain) –
//  Bereinigung, Kürzen auf die Hauptdomain, zweiteilige Länderendungen,
//  Freemail-Ausschluss und unbrauchbare Adressen.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct SenderDomainTests {

    /// Subdomains werden auf die Hauptdomain gekürzt.
    @Test func subdomainIsShortenedToMainDomain() {
        #expect(SenderDomain.iconDomain(forAddress: "noreply@mailing.zalando.de") == "zalando.de")
        #expect(SenderDomain.iconDomain(forAddress: "no-reply@accounts.google.com") == "google.com")
        #expect(SenderDomain.iconDomain(forAddress: "noreply@github.com") == "github.com")
    }

    /// Zweiteilige Länderendungen behalten drei Teile.
    @Test func twoPartSuffixKeepsThreeLabels() {
        #expect(SenderDomain.iconDomain(forAddress: "news@mail.bbc.co.uk") == "bbc.co.uk")
        #expect(SenderDomain.mainDomain(of: "shop.example.com.au") == "example.com.au")
    }

    /// Schreibweise, Leerraum und abschließender Punkt werden bereinigt.
    @Test func domainIsCleaned() {
        #expect(SenderDomain.domain(ofAddress: " Info@Firma.DE. ") == "firma.de")
    }

    /// Freemail-Anbieter bekommen kein Logo, auch über Subdomains.
    @Test func freemailGivesNoDomain() {
        #expect(SenderDomain.iconDomain(forAddress: "anna@gmail.com") == nil)
        #expect(SenderDomain.iconDomain(forAddress: "ben@web.de") == nil)
        #expect(SenderDomain.iconDomain(forAddress: "carl@mx.gmx.net") == nil)
    }

    /// Unbrauchbare Adressen ergeben keine Domain.
    @Test func unusableAddressGivesNoDomain() {
        #expect(SenderDomain.domain(ofAddress: "ohne-at") == nil)
        #expect(SenderDomain.domain(ofAddress: "x@localhost") == nil)
        #expect(SenderDomain.domain(ofAddress: "x@firma..de") == nil)
        #expect(SenderDomain.domain(ofAddress: "x@fir ma.de") == nil)
        #expect(SenderDomain.domain(ofAddress: "x@müller.de") == nil)
    }
}
