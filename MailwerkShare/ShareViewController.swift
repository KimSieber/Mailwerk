//
//  ShareViewController.swift
//  MailwerkShare
//
//  Zweck: Einstieg der Teilen-Erweiterung auf iPhone und iPad. Das System
//  legt diesen Controller an, wenn im Teilen-Menü „Mailwerk“ gewählt wird.
//  Er reicht die geteilten Elemente an die SwiftUI-Wurzelansicht weiter
//  und beendet die Erweiterung, wenn diese fertig ist.
//
//  Das Fenster lässt sich nicht durch Herunterwischen schließen, nur über
//  „Schließen“ – so geht eine begonnene Mail nicht versehentlich verloren
//  (das Verfassen-Fenster fragt beim Schließen wie in der App nach).
//
//  Abgrenzung: Inhalt und Ablauf → ShareRootView.
//
//  Abhängigkeiten: UIKit, SwiftUI, ShareRootView, SharedInput.
//

import UIKit
import SwiftUI

/// Einstieg der Teilen-Erweiterung (in Info.plist als
/// `NSExtensionPrincipalClass` eingetragen).
final class ShareViewController: UIViewController {

    /// Bettet die SwiftUI-Wurzelansicht ein.
    ///
    /// Verarbeitung: Übernimmt je geteiltem Element dessen Anbieter und
    /// Überschrift (Safari: Seitentitel) und zeigt die Wurzelansicht
    /// bildschirmfüllend.
    override func viewDidLoad() {
        super.viewDidLoad()
        isModalInPresentation = true

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

        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
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
