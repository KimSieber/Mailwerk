# Mailwerk – Entwicklungsdokumentation v0.1.13

2026-10-13 · Signaturen (Jira MW-2), Abruf je Postfach ein-/ausschalten, Entwurf sichern (Jira MW-16, Teil 1)

---

## Zusammenfassung

v0.1.13 wurde in drei Paketen mit je eigenem Test- und Commit-Punkt umgesetzt:

| Paket | Inhalt | Commit | Details |
|---|---|---|---|
| **v0.1.13a** | Signaturen: HTML zurück in den Editor, Links und Bilder im Editor, Signatur-Pflege je Postfach mit iCloud-Abgleich, Signatur beim Verfassen | `c63552f` | `Mailwerk_v0.1.13a_Entwicklungsdokumentation.md` |
| **v0.1.13b** | Abruf je Postfach ein-/ausschalten (nur dieses Gerät), Pause-Kennzeichen | `405af3f` | `Mailwerk_v0.1.13b_Entwicklungsdokumentation.md` |
| **v0.1.13c** | Als Entwurf sichern (c1) | dieser Commit | unten |

**Bewusst offen geblieben:** c2 „Entwurf weiterbearbeiten“ (Entwurf aus dem Ordner „Entwürfe“ im Verfassen-Fenster öffnen, alte Fassung ersetzen, „Beantwortet“ beim Senden eines Antwort-Entwurfs). Das Format der Entwürfe ist dafür schon vollständig angelegt (Marken und Datenblock, siehe unten). v0.1.13 wurde nach c1 abgeschlossen; c2 ist in die Planung übernommen (siehe Übergabe v0.1.14).

Tests: 477 → 519 (a) → 523 (b) → **528**, alle grün.

---

## v0.1.13a – Signaturen (Kurzfassung)

- **Editor:** fehlertoleranter HTML-Rückweg (`HTMLRichTextParser`, `RichTextImport`), Knopf „Link“ (`LinkInput`), Bilder im Editor als eingebettete Bilder (`MailImageAttachment`, `EditorImageData`).
- **Pflege:** je Postfach eine Signatur, Art „Einfach“ (Editor mit Logo-Knopf) oder „HTML“ (Code/Vorschau, `CodeTextEditor` ohne typografische Anführungszeichen), Logo als Platzhalter `<img src="logo">`, gespeichert in SwiftData/CloudKit (`AccountSignature`, `SignatureStore`), auf allen Geräten gleich.
- **Verfassen:** einfache Signatur markiert im Mailtext (frei bearbeitbar), HTML-Signatur als bearbeitbarer Block (`SignatureBlockView`, `contenteditable`), beim Postfachwechsel immer ausgetauscht – auch nach Löschen.
- **Beobachtet:** Das Ablege-Werkzeug von Claude schrieb bei wiederholtem gleichem Zwischenpfad teils den alten Inhalt; seither frischer Pfad und Prüfsummenvergleich nach jeder Lieferung.

## v0.1.13b – Abruf je Postfach (Kurzfassung)

- Schalter „Abruf“ je Postfach (Postfachliste und „Postfach bearbeiten“), nur für dieses Gerät (`UserDefaults`), standardmäßig an.
- Ausgeschaltet: keine Abrufrunde über „Alle Eingänge“, Mails in den Sammelsichten ausgeblendet, Ordnerliste nur aus dem Cache; Öffnen des Posteingangs ruft wie in der Runde ab (Spamfilter, Posteingang, Spam-Ordner), andere Ordner einzeln.
- Kennzeichen: orangefarbener Kreis mit weißem Pause-Zeichen vor dem Namen.
- `MARKETING_VERSION` von „0.1.13a“ auf **0.1.13** korrigiert (Apple nimmt nur Zahlen mit Punkten an).

---

## v0.1.13c – Als Entwurf sichern

**Problem:** Beim Schließen eines Fensters mit Eingaben gab es nur „Entwurf verwerfen?“ mit „Verwerfen“ oder „Weiter bearbeiten“. Eine angefangene Mail ließ sich nicht für später sichern.

**Entschieden:**
1. Beim Schließen drei Möglichkeiten: **Als Entwurf sichern** · **Verwerfen** · **Weiter bearbeiten**; der Text passt für alle („Nachricht schließen?“).
2. **Offline** ist „Als Entwurf sichern“ ausgegraut; der Text nennt den Grund. Nur Verwerfen und Weiter bearbeiten sind dann möglich.
3. **Ohne Absender** Hinweis „Bitte zuerst einen Absender wählen“, das Fenster bleibt offen.
4. Ablage im Ordner „Entwürfe“ des Absende-Postfachs; fehlt er, nach kurzer Rückfrage anlegen („Drafts“, Mailwerk zeigt ihn als „Entwürfe“).
5. Kein automatisches Zwischenspeichern – Sichern ist ein bewusster Vorgang.
6. Für c2 festgelegt: Tipp auf eine Mail im Ordner „Entwürfe“ öffnet das Verfassen-Fenster; beim Senden oder erneuten Sichern verschwindet die alte Fassung endgültig (nicht über den Papierkorb); ein gesendeter Antwort-Entwurf setzt „Beantwortet“ am Original; beim Wiederöffnen kommen Absender, Empfänger (auch Bcc), Betreff, Text mit Formaten und Bildern, Signatur (weiter austauschbar), Zitat und Anhänge vollständig zurück; Entwürfe aus anderen Programmen kommen vereinfacht in den Editor.

**Lösung:**
- **`DraftFormat` (neu, ohne Oberfläche):** Der Entwurf ist eine gewöhnliche Mail; im HTML stehen unsichtbare Kommentar-Marken:
  - `<!--mailwerk-entwurf:daten …-->` – Datenblock (JSON, Base64): Art (neu/Antwort/Allen antworten/Weiterleiten), Bcc, Bezug zur Originalmail (Cache-Kennung, Postfach, Ordner, UID), In-Reply-To, References, Art der Signatur.
  - je Teil Beginn- und End-Marke: `text` (vor der Signatur), `signatur`, `text-nach`, `zitat`.
  - `parse` zerlegt ausschließlich per Textsuche; ohne Datenblock (fremder Entwurf) → `nil`.
- **`DraftService` (neu):** baut die Nachricht wie beim Versand (`MailSendService.makeEmail`, jetzt intern nutzbar), ergänzt den Bcc-Header (`addingBccHeader`, gemeinsam mit der Gesendet-Kopie), findet den Entwürfe-Ordner (SPECIAL-USE `\Drafts`, sonst Namen „Drafts“, „Draft“, „Entwürfe“ – lesbar dekodiert) und legt mit `\Draft` und `\Seen` ab (IMAP APPEND). Fehlt der Ordner: `DraftError.draftsFolderMissing`; `createDraftsFolder` legt ihn über `MailActionService.createFolder` an. Die gemeldete UID (UIDPLUS) steht für c2 bereit.
- **`ComposeViewModel`:** `saveDraft(createFolder:)` lädt wie beim Senden fehlende Anhänge und Bilder der Originalmail nach (scheitert das, wird nicht gesichert), baut das HTML mit Marken (`draftHTML`: Mailtext an der einfachen Signatur geteilt, HTML-Signatur als Signatur-Teil) und meldet `saved`, `needsDraftsFolder` oder `failed`.
- **`SignatureEditing.split`:** teilt den Mailtext in Text davor, Signatur, Text danach.
- **`Dialogs`:** `ConfirmationRequest` kann einen dritten Knopf (`secondary`) tragen, auch ausgegraut.
- **`ComposeView`:** Rückfrage „Nachricht schließen?“ (Text je nach Verbindung), Ablauf „Kein Absender“ → Hinweis, „Ordner ‚Entwürfe‘ anlegen?“ → Anlegen und erneut sichern; während des Sicherns Ladeanzeige statt Senden-Knopf.

---

## Geänderte Dateien (Paket c)

```
Mailwerk/
├── Services/
│   ├── Drafts/
│   │   ├── DraftFormat.swift             # neu
│   │   └── DraftService.swift            # neu
│   ├── MailSendService.swift             # makeEmail intern, addingBccHeader
│   └── Signatures/SignatureEditing.swift # split
├── ViewModels/
│   └── ComposeViewModel.swift            # saveDraft, draftHTML
└── Views/
    ├── ComposeView.swift                 # Rückfrage „Nachricht schließen?“
    └── Dialogs.swift                     # dritter Knopf
MailwerkTests/
├── DraftFormatTests.swift                # neu, 4 Tests
└── SignatureComposeTests.swift           # +1 (Zerlegen an der Signatur)
```

Pakete a und b: siehe deren Entwicklungsdokumentationen.

---

## Testverfahren (Paket c)

**Automatisch:** 528 Tests (Simulator), alle grün; das Entwurfsformat zusätzlich unter Linux.

**Manuell (Simulator), Mails nur an sich selbst:**
- Neue Mail mit Text, Signatur und Foto → ✕ → „Als Entwurf sichern“: Entwurf im Ordner „Entwürfe“ in Mailwerk und im Webmail, sauber lesbar.
- Antwort als Entwurf: im Webmail mit Zitat.
- Offline: „Als Entwurf sichern“ ausgegraut, Text nennt den Grund.
- Ohne Absender: Hinweis, Fenster bleibt offen.

---

## Beobachtungen

- Ein Tipp auf einen Entwurf öffnet ihn bis zur Umsetzung von c2 noch in der Leseansicht.
- Das CloudKit-Schema (Signaturen) ist bisher nur in der Development-Umgebung angelegt; vor dem App-Store-Gang nach Production übertragen.
- Ablage von Dateien durch Claude: nach jeder Lieferung Prüfsummen auf dem Mac vergleichen (siehe v0.1.13a).

## Nächste Schritte

- **v0.1.14 – Fehler-Patch-Version** (Inhalt vorab abstimmen).
- **v0.1.15 – Teilen mit Mailwerk** (Share Extension, MW-15), danach v0.1.16 Suche (MW-6).
- **c2 „Entwurf weiterbearbeiten“** einplanen (Vorschlag: in v0.1.14, da Entwürfe sonst nur außerhalb von Mailwerk weiterbearbeitet werden können).
