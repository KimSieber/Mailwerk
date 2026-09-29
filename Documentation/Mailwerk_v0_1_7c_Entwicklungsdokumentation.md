# Mailwerk – Entwicklungsdokumentation v0.1.7c

2026-09-29 · Korrekturen: HTML-Darstellung, Teilen, Drucken

---

## Zusammenfassung

Version 0.1.7c behebt drei Probleme, die den produktiven Einsatz einschränkten: HTML-Mails mit festen Breiten wurden im Hochformat abgeschnitten, Teilen und Drucken waren deaktiviert, und das Aktionsmenü ließ sich bei komplexen Mails nicht scrollen.

---

## Änderungen

### HTML-Darstellung (HTMLMailView)

- **Feste Breiten überstimmt:** CSS-Regel `max-width: 100% !important` und `width: auto !important` auf allen Tabellen, Divs, Zellen und Bildern. HTML-Mails mit festen Pixelbreiten (z. B. Parka-Quittungen mit `width="600"`) passen sich jetzt an die Bildschirmbreite an.
- **Höhenmessung:** Zweite Messung nach 300 ms, weil einige Mails nach dem ersten Layout noch CSS-Transitionen auslösen.
- **Interaktion deaktiviert:** `isUserInteractionEnabled = false` auf dem WKWebView. Der äußere SwiftUI-ScrollView übernimmt das Scrollen. Verhindert, dass komplexe HTML-Mails (Google u. a.) Gesten verschlucken und das Aktionsmenü blockieren.

### Drucken (MailPrinter)

- **WKWebView statt UIMarkupTextPrintFormatter:** `UIMarkupTextPrintFormatter` konnte nur einfaches HTML rendern; komplexe Tabellenlayouts blieben leer. Der neue `MailPrinter` rendert den Inhalt in einem temporären WKWebView und übergibt dessen `viewPrintFormatter()` an den Druckdialog.
- **Anhänge im Ausdruck:** Unter dem Mail-Body erscheint ein Abschnitt „Anlagen (n):" mit Typ-Symbol, Dateiname und Dateigröße.
- **Mail-Header:** Von, An, Kopie, Datum und Betreff werden über dem Body gedruckt.

### Teilen (MailShareSheet)

- **HTML-Datei statt NSAttributedString:** `NSAttributedString(data:options:.html)` scheiterte stillschweigend bei komplexen HTML-Mails. Jetzt wird eine temporäre HTML-Datei mit dem Betreff als Dateiname erzeugt, die den vollen Header, Body und die Anhangsliste enthält.
- **Anhänge als separate Dateien:** Lokal vorhandene Anhänge werden als eigene Dateien mitgegeben.

### Aktionsmenü (MessageDetailView)

- **Spam-Aktionen als Untermenü:** Die vier Spam-/Vertrauens-Aktionen sind jetzt unter „Spam / Vertrauen" zusammengefasst. Das Hauptmenü hat damit vier Einträge weniger.

---

## Projektstruktur (Änderungen gegenüber v0.1.7b)

```
Mailwerk/Views/
├── HTMLMailView.swift         # CSS-Fix, Interaktion deaktiviert, Höhenmessung
├── MessageDetailView.swift    # Teilen/Drucken aktiviert, Anhänge im Ausdruck, Spam-Untermenü
├── MailPrinter.swift          # NEU – Druck über temporären WKWebView
└── MailShareSheet.swift       # NEU – Teilen als HTML-Datei + Anhänge
```

---

## Bekannte Einschränkungen

| Einschränkung | Einordnung |
|---|---|
| Links in HTML-Mails sind nicht klickbar (WebView-Interaktion deaktiviert) | Bewusst, um Menü-Gesten zuverlässig zu halten; Link-Handling per Overlay in späterer Version |
| Menü bei einzelnen komplexen Mails knapp am unteren Rand | Beobachten mit weiteren Beispielen; grundsätzlich bedienbar |
| Parka-Mail: Body beginnt auf Seite 2 im Druck | Korrekt, da die Tabelle nicht zwischen Header und Seitenumbruch passt |

---

## Tests

Keine neuen Unit-Tests. Manuell geprüft: HTML-Darstellung (Parka, Google, Newsletter), Drucken mit/ohne Anhänge, Teilen mit/ohne Anhänge, Menü-Scrolling, Scrollen in der Mail-Ansicht.

---

## Abhängigkeiten / Xcode-Konfiguration

Unverändert.
