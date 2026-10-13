//
//  AccountSignature.swift
//  Mailwerk
//
//  Zweck: Speichermodell einer Signatur für SwiftData – ein Datensatz je
//  Postfach, über CloudKit auf alle Geräte abgeglichen. Das Logo liegt
//  als externe Datei (in CloudKit als eigenes Asset), damit der Datensatz
//  klein bleibt.
//
//  CloudKit-Vorgaben für SwiftData: kein `@Attribute(.unique)`, jede
//  Eigenschaft mit Standardwert oder optional. Doppelte Datensätze für
//  dasselbe Postfach werden deshalb beim Lesen aufgelöst (der neueste
//  gilt) und beim nächsten Speichern entfernt.
//
//  Abgrenzung: Lesen und Schreiben → SwiftDataSignatureStorage; Wert-Typ
//  und Regeln → SignatureRules.
//
//  Abhängigkeiten: Foundation, SwiftData, SignatureItem.
//

import Foundation
import SwiftData

/// Speichermodell einer Signatur.
@Model
final class AccountSignature {
    /// Kennung des Datensatzes.
    var id: UUID = UUID()
    /// Kennung des Postfachs, zu dem die Signatur gehört.
    var accountID: UUID = UUID()
    /// Art als Text (für SwiftData/CloudKit).
    var kindRaw: String = SignatureKind.simple.rawValue
    /// HTML der Signatur mit Logo-Platzhalter.
    var html: String = ""
    /// Bilddaten des Logos; außerhalb der Datenbank gespeichert.
    @Attribute(.externalStorage) var logoData: Data?
    /// MIME-Typ des Logos.
    var logoMimeType: String?
    /// Zeitpunkt der letzten Änderung.
    var modifiedAt: Date = Date()

    /// Legt einen Datensatz aus einem Wert an.
    ///
    /// - Parameter item: Signatur als Wert.
    init(_ item: SignatureItem) {
        accountID = item.accountID
        apply(item)
    }

    /// Übernimmt alle Inhalte eines Werts (die Kennungen bleiben).
    ///
    /// - Parameter item: Signatur als Wert.
    func apply(_ item: SignatureItem) {
        kindRaw = item.kind.rawValue
        html = item.html
        logoData = item.logoData
        logoMimeType = item.logoMimeType
        modifiedAt = item.modifiedAt
    }

    /// Datensatz als Wert; unbekannte Arten (etwa aus einer neueren
    /// App-Version) gelten als HTML – so bleibt der Code unverändert.
    var item: SignatureItem {
        SignatureItem(
            accountID: accountID,
            kind: SignatureKind(rawValue: kindRaw) ?? .html,
            html: html,
            logoData: logoData,
            logoMimeType: logoMimeType,
            modifiedAt: modifiedAt
        )
    }
}
