//
//  ShareViewController.swift
//  MailwerkShareMac
//
//  Zweck: Einstieg der Teilen-Erweiterung auf dem Mac. Das System legt
//  diesen Controller an, wenn im Teilen-Menü (Finder, Fotos, Safari …)
//  „Mailwerk“ gewählt wird. Er reicht die geteilten Elemente an dieselbe
//  SwiftUI-Wurzelansicht wie auf dem iPhone weiter und beendet die
//  Erweiterung, wenn diese fertig ist.
//
//  Ohne Vorlagedatei (xib): Die Ansicht wird im Code angelegt; ihre Größe
//  entspricht dem Verfassen-Fenster der App (MacSheetSize.composer).
//  Feinschliff der Mac-Gestaltung folgt mit v0.2.x.
//
//  Abgrenzung: Inhalt und Ablauf → ShareRootView; Gegenstück für
//  iPhone/iPad → MailwerkShare/ShareViewController.
//
//  Abhängigkeiten: AppKit, SwiftUI, ShareRootView, SharedInput,
//  MacSheetSize.
//

import AppKit
import SwiftUI

/// Einstieg der Teilen-Erweiterung auf dem Mac (in Info.plist als
/// `NSExtensionPrincipalClass` eingetragen).
final class ShareViewController: NSViewController {

    /// Kein Nib: verhindert, dass AppKit eine Vorlagedatei sucht.
    override var nibName: NSNib.Name? { nil }

    /// Legt die Ansicht an und bettet die SwiftUI-Wurzelansicht ein.
    ///
    /// Verarbeitung: Übernimmt je geteiltem Element dessen Anbieter und
    /// Überschrift und zeigt die Wurzelansicht in der Größe des
    /// Verfassen-Fensters.
    override func loadView() {
        let size = NSSize(width: MacSheetSize.composer.width, height: MacSheetSize.composer.height)
        view = NSView(frame: NSRect(origin: .zero, size: size))
        preferredContentSize = size

        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let inputs = items.map { item in
            SharedInput(
                providers: item.attachments ?? [],
                title: (item.attributedTitle ?? item.attributedContentText)?.string
            )
        }
        let root = ShareRootView(inputs: inputs) { [weak self] completed in
            self?.finish(completed: completed)
        }

        let host = NSHostingView(rootView: root)
        host.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: view.topAnchor),
            host.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    /// Beendet die Erweiterung und gibt die teilende App wieder frei.
    ///
    /// - Parameter completed: `true` nach Versand bzw. Sichern als Entwurf,
    ///   `false` beim Verwerfen oder Abbrechen.
    private func finish(completed: Bool) {
        if completed {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            extensionContext?.cancelRequest(
                withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
            )
        }
    }
}
