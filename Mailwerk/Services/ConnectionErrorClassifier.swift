//
//  ConnectionErrorClassifier.swift
//  Mailwerk
//
//  Unterscheidet Verbindungsfehler (kein Netz, Server nicht erreichbar,
//  Verbindung abgebrochen) von echten Fehlern (Anmeldung, Protokoll).
//  Verbindungsfehler meldet die App nicht per Alert, sondern still im
//  Titel – offline zu arbeiten ist ein normaler Zustand.
//
//  Die SwiftMail-eigenen Fälle (`IMAPError.connectionFailed`, `.timeout`)
//  prüft `MailFetchService.isConnectionError`, weil dieser Typ hier
//  nicht verfügbar ist. Hier stehen nur Foundation- und NIO-Fehler.
//

import Foundation

nonisolated enum ConnectionErrorClassifier {

    /// Fehlertypen von SwiftNIO, die einen Verbindungsabbruch bedeuten.
    /// Per Typname geprüft, weil NIO im App-Target nicht direkt
    /// importiert wird.
    static let connectionErrorTypeNames: Set<String> = [
        "NIOPosix.NIOConnectionError",
        "NIOCore.ChannelError",
        "NIOCore.IOError"
    ]

    static let urlErrorCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut,
        .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
        .internationalRoamingOff, .dataNotAllowed
    ]

    static let posixErrorCodes: Set<Int32> = [
        ENETDOWN, ENETUNREACH, EHOSTUNREACH, EHOSTDOWN,
        ECONNREFUSED, ECONNRESET, ECONNABORTED, ETIMEDOUT, ENOTCONN, EPIPE
    ]

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
