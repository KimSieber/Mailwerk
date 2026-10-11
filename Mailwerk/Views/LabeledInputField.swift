//
//  LabeledInputField.swift
//  Mailwerk
//
//  Zweck: Eingabezeile für Formulare mit fester Beschriftung links und dem
//  Eingabefeld rechts, das ein Beispiel als Platzhalter zeigt – etwa
//  „E-Mail-Adresse“ | „z. B. max.mueller@mail.org“.
//
//  Ein reines `TextField` zeigt auf iPhone und iPad seine Bezeichnung nur
//  als Platzhalter; sobald etwas eingetragen ist, verschwindet sie. Hier
//  bleibt die Beschriftung immer sichtbar, und das Beispiel erklärt, was
//  hineingehört. Auf dem Mac stellt das Formular die Zeile genauso dar.
//
//  Eingabearten (Tastatur, Autokorrektur) setzt der Aufrufer mit den
//  Modifiern aus PlatformInputModifiers an diese Zeile; sie wirken auf das
//  enthaltene Feld.
//
//  Abgrenzung: Formulare → AddAccountView, EditAccountView.
//
//  Abhängigkeiten: SwiftUI.
//

import SwiftUI

/// Formularzeile mit fester Beschriftung und Beispiel als Platzhalter.
struct LabeledInputField: View {
    /// Beschriftung links, z. B. „E-Mail-Adresse“.
    let label: String
    /// Platzhalter im leeren Feld, z. B. „z. B. max.mueller@mail.org“.
    let example: String
    /// Eingegebener Text.
    @Binding var text: String
    /// `true` für verdeckte Eingabe (Passwort).
    var isSecure = false

    /// Beschriftung und rechtsbündiges Eingabefeld.
    var body: some View {
        LabeledContent(label) {
            Group {
                if isSecure {
                    SecureField(label, text: $text, prompt: Text(example))
                } else {
                    TextField(label, text: $text, prompt: Text(example))
                }
            }
            .labelsHidden()
            .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Vorschau

#Preview {
    @Previewable @State var address = ""
    @Previewable @State var name = "Max Müller"

    Form {
        LabeledInputField(label: "Absendername", example: "z. B. Max Müller", text: $name)
        LabeledInputField(label: "E-Mail-Adresse", example: "z. B. max.mueller@mail.org", text: $address)
    }
}
