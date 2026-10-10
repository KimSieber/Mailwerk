//
//  UserFacingError.swift
//  Mailwerk
//
//  Zweck: Kennzeichnet Fehler, deren Meldung sich direkt an den Nutzer
//  richtet (z. B. ungültiger Ordnername, fehlendes Passwort). Dienste,
//  die technische Fehler zu einer allgemeinen Meldung zusammenfassen,
//  reichen solche Fehler unverändert durch.
//
//  So muss ein allgemeiner Helfer keine einzelnen Fehlertypen anderer
//  Bausteine kennen – der Fehlertyp selbst erklärt sich für zuständig.
//
//  Abgrenzung: Anzeige der Meldung → Dialogs (`AlertItem`).
//
//  Abhängigkeiten: keine.
//

import Foundation

/// Fehler mit einer Meldung, die unverändert beim Nutzer ankommen soll.
nonisolated protocol UserFacingError: LocalizedError {}
