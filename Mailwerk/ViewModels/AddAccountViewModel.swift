//
//  AddAccountViewModel.swift
//  Mailwerk
//
//  Created by Kim Sieber on 18.09.26.
//

import Foundation
import Observation

@Observable
final class AddAccountViewModel {
    var displayName = ""
    var senderName = ""
    var username = ""
    var password = ""

    var imapHost = ""
    var imapPort = "993"
    var smtpHost = ""
    var smtpPort = "587"

    var isTesting = false
    var testResult: TestResult?

    enum TestResult: Equatable {
        case success
        case failure(String)
    }

    var isValid: Bool {
        !displayName.isEmpty && !username.isEmpty && !password.isEmpty
            && !imapHost.isEmpty && !smtpHost.isEmpty
            && Int(imapPort) != nil && Int(smtpPort) != nil
    }

    @MainActor
    func testConnection() async {
        guard let imapPortInt = Int(imapPort), let smtpPortInt = Int(smtpPort) else {
            testResult = .failure("Ungültiger Port")
            return
        }
        isTesting = true
        defer { isTesting = false }

        do {
            try await MailConnectionTester.testIMAP(
                host: imapHost, port: imapPortInt, username: username, password: password
            )
            try await MailConnectionTester.testSMTP(
                host: smtpHost, port: smtpPortInt, username: username, password: password
            )
            testResult = .success
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }

    func makeAccount() -> MailAccount {
        MailAccount(
            displayName: displayName,
            senderName: senderName,
            username: username,
            imapHost: imapHost,
            imapPort: Int(imapPort) ?? 993,
            smtpHost: smtpHost,
            smtpPort: Int(smtpPort) ?? 587
        )
    }
}
