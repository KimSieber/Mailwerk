//
//  OAuthPKCE.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 17.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Schutz der Anmeldung per PKCE (RFC 7636) und zufällige Werte für
//  den Anmeldeablauf.
//
//  Hintergrund: Eine App kann kein Geheimnis vor ihren Nutzern verbergen;
//  sie ist ein „öffentlicher Client“. Damit ein abgefangener
//  Anmelde-Code wertlos ist, erzeugt Mailwerk vor jeder Anmeldung einen
//  zufälligen Prüfwert (`verifier`) und schickt nur dessen SHA-256-Abbild
//  (`challenge`) ins Anmeldefenster. Den Code tauscht der Anbieter nur
//  gegen Tokens, wenn beim Tausch der passende Prüfwert mitkommt.
//
//  `state` ist ein zweiter Zufallswert: Er geht ins Anmeldefenster und
//  muss unverändert zurückkommen – sonst stammt die Rückkehr nicht aus
//  dieser Anmeldung.
//
//  Abgrenzung: Anmelde-Adresse bauen und Rückkehr prüfen →
//  OAuthAuthorization.
//
//  Abhängigkeiten: Foundation, CryptoKit (SHA-256; unter Linux für die
//  Vorprüfung swift-crypto), Security (Zufall).
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#if canImport(Security)
import Security
#endif

/// Prüfwert und Abbild für PKCE.
nonisolated struct OAuthPKCE: Equatable, Sendable {
    /// Länge des Zufalls für den Code-Verifier in Byte (256 Bit, RFC 7636
    /// empfiehlt 32 Byte).
    static let verifierByteCount = 32
    /// Zufälliger Prüfwert; bleibt in der App und geht erst beim Tausch mit.
    let verifier: String
    /// SHA-256-Abbild des Prüfwerts (Base64-URL); geht ins Anmeldefenster.
    let challenge: String
    /// Verfahren des Abbilds; immer „S256“.
    let method = "S256"

    /// Erzeugt Prüfwert und Abbild.
    ///
    /// Verarbeitung: 32 Zufallsbytes ergeben als Base64-URL 43 Zeichen –
    /// die Mindestlänge laut RFC 7636.
    ///
    /// - Returns: Neuer Prüfwert mit Abbild.
    /// - Throws: `OAuthError.randomUnavailable`, wenn das System keinen
    ///   Zufall liefert.
    static func make() throws -> OAuthPKCE {
        let verifier = try randomString(byteCount: Self.verifierByteCount)
        return OAuthPKCE(verifier: verifier, challenge: challenge(for: verifier))
    }

    /// Bildet das Abbild zu einem Prüfwert.
    ///
    /// - Parameters:
    ///   - verifier: Prüfwert.
    /// - Returns: SHA-256 der ASCII-Bytes, als Base64-URL ohne Füllzeichen.
    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    /// Erzeugt eine zufällige Zeichenkette für `state` oder den Prüfwert.
    ///
    /// - Parameter byteCount: Anzahl der Zufallsbytes.
    /// - Returns: Zufallsbytes als Base64-URL ohne Füllzeichen.
    /// - Throws: `OAuthError.randomUnavailable`, wenn das System keinen
    ///   Zufall liefert.
    static func randomString(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        #if canImport(Security)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else { throw OAuthError.randomUnavailable }
        #else
        var generator = SystemRandomNumberGenerator()
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max, using: &generator) }
        #endif
        return base64URL(Data(bytes))
    }

    /// Kodiert Bytes als Base64-URL (RFC 4648 §5) ohne Füllzeichen.
    ///
    /// - Parameter data: Bytes.
    /// - Returns: Kodierte Zeichenkette mit „-“ und „_“ statt „+“ und „/“.
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
