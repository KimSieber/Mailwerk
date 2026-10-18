# Mailwerk – Hinweise für Claude

## Dokumentation (`Documentation/`)

Das Repository ist **öffentlich**. Alles unter `Documentation/` (außer `Documentation/Intern/`) kann jeder lesen.

### Was wohin gehört

- **`Documentation/`** – nur Dokumente, die ein späterer Leser zur Einarbeitung braucht:
  - `Mailwerk_vX.Y.Z_Entwicklungsdokumentation.md` (Stand einer Version),
  - Konzepte mit getroffenen Grundsatzentscheidungen,
  - die Projekt-Initialdokumentation.
- **`Documentation/Intern/`** (per `.gitignore` ausgeschlossen, wird nie gepusht) – alles, was nur für die laufende Arbeit gebraucht wird:
  - Aufträge und Übergaben für neue Chats (`Mailwerk_Auftrag_neuer_Chat_*.md`),
  - Zwischenstände, Fehleranalysen zum Weitermachen, Code-Reviews als Arbeitsliste,
  - Notizen mit persönlichen Angaben.

Im Zweifel ein neues Dokument zuerst in `Intern/` ablegen und nachfragen.

### Keine persönlichen Bezüge in öffentlichen Dokumenten

Beim Schreiben **jeder** Dokumentation unter `Documentation/` gilt:

- **Keine Personennamen** aus dem Projektumfeld, keine Angaben zu Familie, Partner, Arbeitgeber, Kunden oder privaten Lebensumständen.
  - Statt „Entschieden (Name):“ → „Entschieden:“
  - Statt „Wunsch von …“ → „Anforderung:“ / „Auf Wunsch …“
  - Statt „… in Xcode gesetzt (Name)“ → „manuell in Xcode“
  - Statt „Name + Angehörige als Tester“ → „zwei Testpersonen“
- **Keine echten E-Mail-Adressen**, Benutzernamen oder Postfachnamen. Platzhalter verwenden: `vorname.nachname@example.com`, `name@example.com`, „Postfach A/B/C“, „eigene Domain“.
- **Keine lokalen Pfade** mit Benutzernamen (z. B. `/Users/<name>/…`) → „lokaler Projektordner“.
- **Keine Namen anderer privater Projekte** → „andere eigene Projekte“.
- Beispiele in Texten mit Fantasienamen (z. B. „Müller, Max“).
- **Erlaubt** sind technische Kennungen, die ohnehin im Code oder in der Repo-URL stehen: Bundle-ID `de.sieber-bw.Mailwerk` (und abgeleitete App-Gruppen, Container, Keychain-Dienste), Repo `KimSieber/Mailwerk`, Anbieter-/Servernamen (manitu, Posteo, GMX, Gmail, Outlook).

Die inhaltliche Aussage bleibt dabei unverändert – nur der Personenbezug fällt weg.

### Prüfung vor dem Abschluss einer Dokumentation

Vor der Übergabe eines Dokuments unter `Documentation/` nach persönlichen Bezügen suchen, z. B.:

```bash
grep -nE "\bKims?\b|Sieber|ordinum|Frau\b|/Users/|@[a-z0-9.-]+\.(de|com)" Documentation/<datei>.md \
  | grep -v "de.sieber-bw\|KimSieber/Mailwerk"
```

Jeder Treffer, der kein erlaubtes technisches Kennzeichen und kein neutrales Beispiel ist, wird umformuliert.
