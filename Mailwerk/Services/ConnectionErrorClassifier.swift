//
//  ConnectionErrorClassifier.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 29.09.2026
//  Geändert: 11.10.2026
//
//  Zweck: Unterscheidet Verbindungsfehler (kein Netz, Server nicht
//  erreichbar, Verbindung abgebrochen) von echten Fehlern (Anmeldung,
//  Protokoll). Verbindungsfehler meldet die App nicht per Alert, sondern
//  still im Titel – offline zu arbeiten ist ein normaler Zustand.
//
//  Abgrenzung: Die SwiftMail-eigenen Fälle (`IMAPError.connectionFailed`,
//  `.timeout`) prüft `MailFetchService.isConnectionError`, weil dieser Typ
//  hier nicht verfügbar ist. Hier stehen nur Foundation- und NIO-Fehler.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Einordnung von Fehlern als Verbindungsfehler.
nonisolated enum ConnectionErrorClassifier {

    /// Fehlertypen von SwiftNIO, die einen Verbindungsabbruch bedeuten.
    /// Per Typname geprüft, weil NIO im App-Target nicht direkt
    /// importiert wird.
    static let connectionErrorTypeNames: Set<String> = [
        "NIOPosix.NIOConnectionError",
        "NIOCore.ChannelError",
        "NIOCore.IOError"
    ]

    /// URLError-Codes, die einen Verbindungsfehler bedeuten.
    static let urlErrorCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut,
        .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
        .internationalRoamingOff, .dataNotAllowed
    ]

    /// POSIX-Fehlercodes, die einen Verbindungsfehler bedeuten.
    static let posixErrorCodes: Set<Int32> = [
        ENETDOWN, ENETUNREACH, EHOSTUNREACH, EHOSTDOWN,
        ECONNREFUSED, ECONNRESET, ECONNABORTED, ETIMEDOUT, ENOTCONN, EPIPE
    ]

    /// Prüft, ob ein Fehler ein Verbindungsfehler ist.
    ///
    /// Verarbeitung: URLError nach Code, NIO-Fehler nach Typname, sonst
    /// POSIX-Fehler nach Code.
    ///
    /// - Parameter error: Aufgetretener Fehler.
    /// - Returns: `true` bei Verbindungsfehlern.
    static func isConnectionError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return urlErrorCodes.contains(urlError.code)
        }
        if connectionErrorTypeNames.contains(String(reflecting: type(of: error))) {
            return true
        }
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            return posixErrorCodes.contains(Int32(nsError.code))
        }
        return false
    }
}
