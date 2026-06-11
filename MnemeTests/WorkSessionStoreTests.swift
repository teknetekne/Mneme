import XCTest
@testable import Mneme

@MainActor
final class WorkSessionStoreTests: XCTestCase {
    func testRecordWorkStartCreatesSession() async throws {
        let store = WorkSessionStore(persistence: InMemoryPersistence())

        let result = try await store.recordWorkStart(date: Date(), time: "09:00", object: "Mneme")

        if case .needsConfirmation = result {
            XCTFail("Unexpected confirmation request for first session.")
        }

        await waitUntil {
            store.sessions.count == 1
        }

        XCTAssertEqual(store.sessions.first?.startTime, "09:00")
        XCTAssertEqual(store.sessions.first?.object, "Mneme")
    }

    func testRecordWorkStartNeedsConfirmationWhenActiveSessionExists() async throws {
        let store = WorkSessionStore(persistence: InMemoryPersistence())
        _ = try await store.recordWorkStart(date: Date(), time: "09:00", object: "Mneme")
        await waitUntil { store.sessions.count == 1 }

        let result = try await store.recordWorkStart(date: Date(), time: "10:00", object: "Other")

        switch result {
        case .success:
            XCTFail("Expected confirmation when an active session exists.")
        case .needsConfirmation(let existingSession):
            XCTAssertEqual(existingSession.startTime, "09:00")
        }
    }

    func testRecordWorkEndCalculatesCrossMidnightDuration() async throws {
        let store = WorkSessionStore(persistence: InMemoryPersistence())
        let startDate = Date()

        _ = try await store.recordWorkStart(date: startDate, time: "23:00", object: "Night shift")
        await waitUntil { store.sessions.count == 1 }

        let endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        let session = try await store.recordWorkEnd(date: endDate, time: "01:00", object: "Night shift")

        XCTAssertEqual(session?.durationMinutes, 120)
    }

    func testRecordWorkEndThrowsWhenPersistenceFails() async throws {
        let persistence = FlakyPersistence()
        let store = WorkSessionStore(persistence: persistence)

        _ = try await store.recordWorkStart(date: Date(), time: "09:00", object: "Mneme")
        await waitUntil { store.sessions.count == 1 }
        persistence.shouldFail = true

        do {
            _ = try await store.recordWorkEnd(date: Date(), time: "10:00", object: "Mneme")
            XCTFail("Expected recordWorkEnd to throw.")
        } catch {
            XCTAssertEqual((error as NSError).localizedDescription, persistence.injectedError.localizedDescription)
        }
    }
}
