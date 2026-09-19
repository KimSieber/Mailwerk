# Mailwerk – Projekt-Initialdokumentation

2026-09-18 · @Someone

## Projektziele

Kim ist mit den vorhandenen Mail-Clients auf iOS/iPad/Mac unzufrieden (träge, funktional überladen, unpassend für den eigenen Anwendungsfall oder kostenpflichtig). Ziel ist ein eigener, schlanker Mail-Client für die eigenen Endgeräte.

- **Kernfunktion:** Unified Inbox über mehrere IMAP-Postfächer verschiedener Anbieter/Server hinweg
- **Zusatzfunktion:** eigener, bequem aus dem Client pflegbarer Spam-Filter (Black-/Whitelist), der Mails automatisch geräteübergreifend in einen `[Spam]`-Ordner verschiebt
- **Zielplattformen:** iOS, iPadOS, macOS – eine Swift/SwiftUI-Codebasis, analog zum bestehenden Muster aus privateCRM und privateKanban
- Kein kommerzielles Projekt, aber bewusst "marketingfähig" benannt und aufgebaut

## Rahmenbedingungen & Grundsatzentscheidungen

**Postfach-Reihenfolge (gestuft):**

1. manitu (eigenes Hosting, mail.manitu.de) – Startpunkt
2. Posteo – zweiter Anbieter, sobald MVP1 steht
3. GMX/Gmail – nur falls Kims Frau das Projekt mitnutzen möchte (aktuell eher unwahrscheinlich); bringt bei Gmail zusätzlichen OAuth2-Aufwand mit sich, da klassische Passwort-Authentifizierung dort nicht mehr möglich ist

**Push-Benachrichtigungen:** nicht für MVP nötig, aber als spätere Ausbaustufe gewünscht. Bewusste Entscheidung: eigener Server statt Drittanbieter-Infrastruktur (wie sie z. B. Spark oder Newton nutzen, die dafür Postfach-Zugangsdaten auf fremden Servern speichern) – Kim möchte seine Zugangsdaten ausschließlich auf eigener Infrastruktur halten.

**Sicherheitsprinzip:** Die 2FA im manitu-Kundenportal bleibt unangetastet und wird für den Mail-Client nicht benötigt – IMAP/SMTP/Sieve authentifizieren separat über das normale Postfach-Passwort.

**Architektur-Muster:** folgt dem etablierten Muster aus anderen Kim-Projekten – Swift/SwiftUI-Client + PHP/MariaDB-Backend, gehostet auf manitu, Deployment über GitHub Actions (lftp).

## Feature-Entscheidungen

**Spam-Filter:** Ziel ist ein schneller Wisch im Client, um eine Mail bzw. deren Absender als Spam zu markieren. Idealer Weg: die Markierung wird direkt als serverseitige Sieve-Regel über ManageSieve (Port 4190) gepflegt – dann greift sie sofort geräteübergreifend, ganz ohne eigenen Hintergrunddienst. Ob manitu diesen externen Zugang freigibt, ist offen (siehe nächster Abschnitt). Falls nicht verfügbar: Fallback über einen eigenen periodischen Dienst (PHP-Cron auf manitu), der per IMAP MOVE verschiebt.

**Anhänge-Vorschau:** Entscheidung getroffen – Nutzung von Apples QuickLook-Framework (`QLPreviewController`), dem gleichen Mechanismus hinter "Vorschau.app" auf dem Mac. Nativ auf iOS, iPadOS und macOS verfügbar, unterstützt PDF und Fotos direkt, geringer Implementierungsaufwand.

**Volltextsuche:** als notwendig eingestuft, kommt in Stufe 2 (nach MVP1). Es gibt kein fertiges Apple-Äquivalent dafür – Empfehlung: eigener lokaler Suchindex mit SQLite FTS5, aufgebaut beim Mail-Sync.

## Offene technische Klärung: ManageSieve bei manitu

Das manitu-Kundenportal weist "E-Mail-Empfangs-Filter: Sieve" und "Spamfilter: rspamd" als vorhandene Technik aus. Ob der externe ManageSieve-Zugriff (Port 4190, RFC 5804) für Kundenpostfächer freigeschaltet ist, ist aber noch ungeklärt.

**Testergebnis (2026-09-18):**

- Über Hotel-WLAN mit NordVPN (NordWisper): "No route to host" – nicht eindeutig, da VPN/Netz die Ursache sein könnte
- Über Mobilfunk-Hotspot ohne VPN, reiner TCP-Connect ohne TLS: "Connection refused" (errno 61) – eindeutig serverseitige Ablehnung, unabhängig vom Client-Netzwerk

**Schlussfolgerung:** Der externe ManageSieve-Zugang ist bei manitu vermutlich nicht freigeschaltet, oder läuft auf einem anderen, undokumentierten Port.

**Nächster Schritt:** Anfrage an den manitu-Support ist gestellt (Stand 2026-09-18), mit der Frage nach genereller Verfügbarkeit, korrektem Hostname/Port und einer alternativen API, falls ManageSieve nicht vorgesehen ist. Das Ergebnis entscheidet über den Weg der Spam-Kennzeichnung (direkte Sieve-Pflege vs. eigener Verschiebedienst, siehe Feature-Entscheidungen).

## Versionsplan / Roadmap

| Version | Inhalt |
| --- | --- |
| 0.1.x (MVP1) | Dialogoberfläche, Postfach-Einrichtung (manitu), Abruf & Anzeige, Senden/Antworten/Weiterleiten (SMTP), Basis-Aktionen (löschen, verschieben, gelesen/ungelesen, Flag) |
| 0.2.x (MVP2) | Volltextsuche (SQLite FTS5), Anlagen-Vorschau (QuickLook) |
| 0.3.x (MVP3) | Spam-Kennzeichnung per Wisch, Black-/Whitelist-Pflege (Umsetzungsweg abhängig von der ManageSieve-Klärung) |
| 0.4.x (Ausbaustufe) | Eigener Push-Server (IDLE + APNs), Posteo-Unterstützung |

Task- und Bug-Verwaltung erfolgt in einem eigenen Jira-Projekt.

## Backlog (ohne feste Version)

- GMX/Gmail-Unterstützung inkl. OAuth2-Implementierung – nur falls Kims Frau das Projekt mitnutzen möchte
- Mehrbenutzer-Unterstützung
- Konversations-Threading
- Optimierung des Offline-Volltextindex
- Vacation-Autoresponder über Sieve

## Namensgebung

Arbeits-/Projekttitel: **Mailwerk** (Entscheidung getroffen, 2026-09-18).

Weitere Kandidaten, noch nicht final verworfen: Briefkasten (gefiel Kim gut, aber nicht seiner Frau), Zustellwerk, Inboxio, Postkutsche.

Verworfen: Postler (Namenskollision – ehemaliger, mittlerweile eingestellter Open-Source-Mail-Client für Linux/Elementary OS).

Vor einer eventuellen Veröffentlichung noch offen: Markenrecherche im DPMA-Register und Namensraum-Check im App Store.

## Nächste Schritte

- [ ] Antwort von manitu-Support zur ManageSieve-Verfügbarkeit abwarten
- [ ] Je nach Antwort: Spam-Architektur endgültig festlegen (direkte Sieve-Pflege vs. eigener Verschiebedienst)
- [ ] Jira-Projekt für Task-/Bug-Tracking anlegen
- [ ] Start MVP1 (0.1.x): UI-Grundgerüst, Postfach-Einrichtung, IMAP-Abruf, SMTP-Versand, Basis-Aktionen
