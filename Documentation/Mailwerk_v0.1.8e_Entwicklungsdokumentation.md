# Mailwerk – Entwicklungsdokumentation v0.1.8e

2026-09-30 · Abgleich beschleunigt und auf den ganzen Ordner ausgeweitet

---

## Zusammenfassung

Der Server-Abgleich aus v0.1.8d holt den Stand eines Ordners jetzt mit **einer einzigen Abfrage** statt mit fünf Suchen: `UID FETCH 1:* (FLAGS)`. Das bringt zweierlei auf einmal:

- **Etwa doppelt so schnell.** Über alle sechs Ordner zusammen 3,5 statt 7,3 Sekunden.
- **Der ganze Ordner statt nur der letzten 30 Tage.** Damit verschwinden auch sehr alte, anderswo gelöschte Mails aus dem Cache, und die Flags aller Mails werden abgeglichen – nicht mehr nur die der jüngsten.

Die Vergleichslogik blieb unverändert. Ausgetauscht wurde nur, wie die Daten beschafft werden.

---

## Geänderte Dateien

```
Mailwerk/Services/
├── MailFetchService.swift                # reconcile: eine Flag-Abfrage statt fünf Suchen;
│                                         #   Messung aus v0.1.8d entfernt
├── MessageStore.swift                    # cachedFlaggedStates entfernt (ohne Nutzer)
└── Sync/ServerReconciliation.swift       # unflagPlan entfernt (ohne Nutzer)
MailwerkTests/
└── ServerReconciliationTests.swift       # 3 Tests der entfernten Sonderbehandlung gestrichen
```

Datenbank: keine Änderung. Unterm Strich 146 Zeilen weniger Code.

---

## Warum das geht

Die 8-KB-Grenze je Antwortzeile (Fund v0.1.8d) greift hier nicht: Bei einer Flag-Abfrage ist **jede Mail eine eigene kurze Zeile**, nicht alle zusammen eine lange. Die Antwort darf also beliebig viele Mails umfassen. Damit entfällt auch das Restrisiko weit verstreuter Suchtreffer aus v0.1.8d.

Weil eine Abfrage nun den ganzen Ordner abdeckt, ist die Sonderbehandlung älterer gekennzeichneter Mails überflüssig geworden und wurde ersatzlos entfernt.

---

## Messergebnisse (manitu, iPhone, 2026-09-30)

| Ordner | Mails | v0.1.8d | v0.1.8e |
|---|---|---|---|
| sieber-bw INBOX | 150 | 1268 ms | **313 ms** |
| sieber-bw Junk | 69 | 1277 ms | **305 ms** |
| ordinum Junk | 992 | – | **418 ms** |
| ordinum INBOX | 5954 | 1330 ms | **818 ms** |
| Kim.Sieber Junk | 513 | 1166 ms | **393 ms** |
| Kim.Sieber INBOX | 8780 | 1273 ms | **1204 ms** |
| **Summe** | | **≈ 7,3 s** | **≈ 3,5 s** |

Grob gerechnet: rund 300 ms Grundkosten je Ordner plus etwa 100 ms je 1000 Mails. Zum Vergleich deckte v0.1.8d bei gleicher oder höherer Laufzeit nur 150 bis 165 Mails je Ordner ab.

**`$Forwarded` wird von manitu gemeldet:** 31 Mails im größten Postfach, 8 in einem weiteren. Die Frage aus v0.1.8d ist damit beantwortet, das Kennzeichen wird korrekt abgeglichen.

---

## Testverfahren

Bisher liefen die Tests auf Produktivdaten: eine Mail im Webmail löschen und schauen, ob sie in Mailwerk verschwindet. Bei über 12.000 Mails ist das nicht vertretbar – Wiederherstellen aus dem Papierkorb heißt, die Mail an der richtigen Stelle wiederzufinden.

**Neues Verfahren:** Im Webmail einen Ordner `Mailwerk-Test` anlegen und Mails hinein **kopieren**, statt sie zu verschieben. Die Originale bleiben unberührt, die Kopien behalten ihr Eingangsdatum – auch Fälle jenseits der 30 Tage lassen sich so prüfen. Mailwerk unterscheidet beim Abgleich nicht zwischen Posteingang und anderen Ordnern; was im Testordner funktioniert, funktioniert auch dort.

Damit geprüft: Löschen einer alten Mail, Setzen und Entfernen von Kennzeichnungen, Gegenprobe, dass nachgeladene Mails und die Ansicht „Mit Kennzeichnung“ unberührt bleiben.

Automatisch: 121 Tests ohne Warnungen.

---

## Nächste Schritte

- **v0.1.9:** Code-Review mit Korrekturen. Offen darin unter anderem: einheitliche Gestaltung der Rückfragen und die Frage, ob eine Testhilfe (Testordner mit erzeugten Mails, nur in Debug-Builds) sinnvoll ist – vorerst zurückgestellt, das Verfahren von Hand genügt.
- **v0.1.10:** Kontextmenü für Mails per langem Drücken, inklusive Mehrfachauswahl.

## Abhängigkeiten / Xcode-Konfiguration

Unverändert gegenüber v0.1.8d.
