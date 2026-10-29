//
//  OAuthTokenServiceTests.swift
//  MailwerkTests
//
//  Zweck: Tests für den OAuthTokenService – Token aus dem Speicher,
//  Erneuern samt neuem Refresh-Token, eine Erneuerung für gleichzeitige
//  Anfragen, Ablauf der Anmeldung (invalid_grant, kein Token), neues Token
//  von einem anderen Gerät, Verbindungsfehler, Übernahme nach Anmeldung
//  und Tausch des Anmelde-Codes. Ohne Netz und ohne Schlüsselbund.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Mailwerk

/// Testhilfe: Refresh-Tokens im Speicher statt im Schlüsselbund.
nonisolated private final class MemoryTokens: @unchecked Sendable {
    /// Schutz für gleichzeitige Zugriffe.
    private let lock = NSLock()
    /// Gespeicherte Tokens je Postfach.
    private var values: [UUID: String] = [:]

    /// Liest ein Token.
    func get(_ id: UUID) -> String? { lock.withLock { values[id] } }
    /// Speichert ein Token.
    func set(_ value: String, _ id: UUID) { lock.withLock { values[id] = value } }
    /// Ablage für den Dienst.
    var storage: RefreshTokenStorage {
        RefreshTokenStorage(read: { self.get($0) }, save: { self.set($0, $1) })
    }
}

/// Testhilfe: verstellbare Uhr.
nonisolated private final class TestClock: @unchecked Sendable {
    /// Schutz für gleichzeitige Zugriffe.
    private let lock = NSLock()
    /// Aktueller Zeitpunkt.
    private var current = Date(timeIntervalSince1970: 1_000_000)
    /// Liest die Zeit.
    func now() -> Date { lock.withLock { current } }
    /// Stellt die Uhr vor.
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

/// Testhilfe: Token-Endpunkt mit vorbereiteten Antworten, zählt Anfragen.
private actor FakeEndpoint {
    /// Vorbereitete Antworten (Status und Inhalt) bzw. Fehler.
    private var responses: [Result<(Int, String), Error>] = []
    /// Formular-Inhalte der Anfragen.
    private(set) var bodies: [String] = []

    /// Hängt eine Antwort an.
    func enqueue(_ status: Int, _ body: String) { responses.append(.success((status, body))) }
    /// Hängt einen Fehler an.
    func enqueue(_ error: Error) { responses.append(.failure(error)) }

    /// Beantwortet eine Anfrage nach kurzer Wartezeit mit der nächsten Antwort.
    func respond(_ request: URLRequest) async throws -> (Data, URLResponse) {
        bodies.append(String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "")
        try await Task.sleep(nanoseconds: 20_000_000)
        switch responses.removeFirst() {
        case .success(let (status, body)):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        case .failure(let error):
            throw error
        }
    }
}

/// Testhilfe: gesammelte Meldungen „neu anmelden“.
private actor Reports {
    /// Meldungen in ihrer Reihenfolge.
    private(set) var events: [Bool] = []
    /// Nimmt eine Meldung auf.
    func add(_ required: Bool) { events.append(required) }
}

@MainActor
struct OAuthTokenServiceTests {

    /// Testhilfe: Postfach.
    private let accountID = UUID()
    /// Testhilfe: Refresh-Tokens.
    private let tokens = MemoryTokens()
    /// Testhilfe: Uhr.
    private let clock = TestClock()
    /// Testhilfe: Token-Endpunkt.
    private let endpoint = FakeEndpoint()
    /// Testhilfe: Meldungen.
    private let reports = Reports()

    /// Testhilfe: Dienst mit den Testhilfen.
    private func makeService() -> OAuthTokenService {
        let endpoint = endpoint, clock = clock, reports = reports
        return OAuthTokenService(
            storage: tokens.storage,
            transport: { try await endpoint.respond($0) },
            now: { clock.now() },
            report: { _, required in await reports.add(required) }
        )
    }

    /// Testhilfe: erfolgreiche Antwort mit neuem Refresh-Token.
    private func success(_ access: String, refresh: String? = nil, expires: Int = 3600) -> String {
        if let refresh {
            return #"{"access_token":"\#(access)","refresh_token":"\#(refresh)","expires_in":\#(expires)}"#
        }
        return #"{"access_token":"\#(access)","expires_in":\#(expires)}"#
    }

    /// Erneuert einmal, speichert das neue Refresh-Token und nutzt danach den Speicher.
    @Test func renewsOnceAndRotatesRefreshToken() async throws {
        tokens.set("R1", accountID)
        await endpoint.enqueue(200, success("A1", refresh: "R2"))
        let service = makeService()

        #expect(try await service.accessToken(accountID: accountID, provider: .microsoft) == "A1")
        #expect(try await service.accessToken(accountID: accountID, provider: .microsoft) == "A1")
        #expect(await endpoint.bodies.count == 1)
        #expect(await endpoint.bodies.first?.contains("refresh_token=R1") == true)
        #expect(tokens.get(accountID) == "R2")
        #expect(await reports.events.isEmpty)
    }

    /// Gleichzeitige Anfragen teilen sich eine Erneuerung.
    @Test func concurrentRequestsShareOneRenewal() async throws {
        tokens.set("R1", accountID)
        await endpoint.enqueue(200, success("A1"))
        let service = makeService()
        let id = accountID

        async let first = service.accessToken(accountID: id, provider: .microsoft)
        async let second = service.accessToken(accountID: id, provider: .microsoft)
        let results = try await [first, second]
        #expect(results == ["A1", "A1"])
        #expect(await endpoint.bodies.count == 1)
        #expect(tokens.get(accountID) == "R1")
    }

    /// Kurz vor dem Ablauf wird erneuert.
    @Test func renewsNearExpiry() async throws {
        tokens.set("R1", accountID)
        await endpoint.enqueue(200, success("A1"))
        await endpoint.enqueue(200, success("A2"))
        let service = makeService()

        #expect(try await service.accessToken(accountID: accountID, provider: .microsoft) == "A1")
        clock.advance(3600 - 299)
        #expect(try await service.accessToken(accountID: accountID, provider: .microsoft) == "A2")
        #expect(await endpoint.bodies.count == 2)
    }

    /// Abgelehntes Refresh-Token: Meldung „neu anmelden“, danach keine Anfrage mehr.
    @Test func invalidGrantRequiresSignInWithoutRetrying() async {
        tokens.set("R1", accountID)
        await endpoint.enqueue(400, #"{"error":"invalid_grant"}"#)
        let service = makeService()

        await #expect(throws: OAuthError.signInRequired) {
            try await service.accessToken(accountID: accountID, provider: .microsoft)
        }
        await #expect(throws: OAuthError.signInRequired) {
            try await service.accessToken(accountID: accountID, provider: .microsoft)
        }
        #expect(await endpoint.bodies.count == 1)
        #expect(await reports.events == [true])
    }

    /// Ein anderes Refresh-Token (etwa von einem anderen Gerät) wird versucht und hebt die Meldung auf.
    @Test func newRefreshTokenAfterRejectionIsTried() async throws {
        tokens.set("R1", accountID)
        await endpoint.enqueue(400, #"{"error":"invalid_grant"}"#)
        await endpoint.enqueue(200, success("A9"))
        let service = makeService()
        _ = try? await service.accessToken(accountID: accountID, provider: .microsoft)

        tokens.set("R9", accountID)
        #expect(try await service.accessToken(accountID: accountID, provider: .microsoft) == "A9")
        #expect(await reports.events == [true, false])
    }

    /// Ohne gespeichertes Refresh-Token: „neu anmelden“ ohne Anfrage.
    @Test func missingRefreshTokenRequiresSignIn() async {
        let service = makeService()
        await #expect(throws: OAuthError.signInRequired) {
            try await service.accessToken(accountID: accountID, provider: .microsoft)
        }
        #expect(await endpoint.bodies.isEmpty)
        #expect(await reports.events == [true])
    }

    /// Fehlendes Netz ist kein Ablauf: Fehler unverändert, keine Meldung.
    @Test func connectionErrorIsPassedThrough() async {
        tokens.set("R1", accountID)
        await endpoint.enqueue(URLError(.notConnectedToInternet))
        let service = makeService()
        await #expect(throws: URLError.self) {
            try await service.accessToken(accountID: accountID, provider: .microsoft)
        }
        #expect(await reports.events.isEmpty)
        #expect(tokens.get(accountID) == "R1")
    }

    /// Nach einer Anmeldung gilt das übernommene Token sofort; die Meldung entfällt.
    @Test func adoptCachesTokenAndClearsSignInRequired() async throws {
        let service = makeService()
        _ = try? await service.accessToken(accountID: accountID, provider: .microsoft)

        let fresh = OAuthTokenSet(accessToken: "A5", refreshToken: "R5", expiresAt: clock.now().addingTimeInterval(3600))
        await service.adopt(fresh, for: accountID)
        #expect(try await service.accessToken(accountID: accountID, provider: .microsoft) == "A5")
        #expect(await endpoint.bodies.isEmpty)
        #expect(await reports.events == [true, false])
    }

    /// Tausch des Codes verlangt ein Refresh-Token.
    @Test func exchangeRequiresRefreshToken() async throws {
        let authorization = try OAuthAuthorization.start(provider: .microsoft, loginHint: nil)
        await endpoint.enqueue(200, success("A1"))
        await endpoint.enqueue(200, success("A2", refresh: "R2"))
        let service = makeService()

        await #expect(throws: OAuthError.missingRefreshToken) {
            try await service.exchange(code: "C", authorization: authorization)
        }
        let tokens = try await service.exchange(code: "C", authorization: authorization)
        #expect(tokens.refreshToken == "R2")
        #expect(await endpoint.bodies.last?.contains("code_verifier=\(authorization.pkce.verifier)") == true)
    }

    /// Ungültiger Code beim Tausch ist kein Ablauf, sondern ein Fehler der Anmeldung.
    @Test func exchangeWithInvalidCodeIsProviderError() async throws {
        let authorization = try OAuthAuthorization.start(provider: .microsoft, loginHint: nil)
        await endpoint.enqueue(400, #"{"error":"invalid_grant"}"#)
        let service = makeService()
        await #expect(throws: OAuthError.providerError(code: "invalid_grant", description: "Der Anmelde-Code ist ungültig oder abgelaufen.")) {
            try await service.exchange(code: "C", authorization: authorization)
        }
        #expect(await reports.events.isEmpty)
    }
}
