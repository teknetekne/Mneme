import Foundation
import Combine
import CloudKit
import CoreData

/// Tracks the state of the Core Data <-> CloudKit mirroring pipeline so
/// views can react to sync progress without changing their appearance.
@MainActor
final class CloudSyncStatusStore: ObservableObject {
    static let shared = CloudSyncStatusStore(container: PersistenceController.shared.container)

    enum Phase: Equatable {
        case idle
        case syncing(activity: Activity)
        case waitingForAccount
        case accountRestricted
        case error(String)
    }

    enum Activity: String {
        case importing = "Pulling changes from iCloud"
        case exporting = "Pushing changes to iCloud"
        case setup = "Preparing CloudKit"
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published private(set) var lastCompletionDate: Date?

    private let container: NSPersistentCloudKitContainer
    private let ckContainer: CKContainer
    private var observers: [NSObjectProtocol] = []

    private init(container: NSPersistentCloudKitContainer) {
        self.container = container
        if let identifier = Bundle.main.object(forInfoDictionaryKey: "iCloudContainerIdentifier") as? String,
           !identifier.isEmpty {
            ckContainer = CKContainer(identifier: identifier)
        } else {
            ckContainer = CKContainer.default()
        }

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: nil) { [weak self] note in
            guard
                let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event
            else { return }
            Task { @MainActor [weak self] in
                self?.handle(event: event)
            }
        })

        observers.append(center.addObserver(forName: .NSPersistentStoreRemoteChange, object: container.persistentStoreCoordinator, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.markRemoteChange()
            }
        })

        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshAccountStatus()
            }
        })

        Task { @MainActor in
            await refreshAccountStatus()
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func refreshAccountStatus() async {
        do {
            let status = try await ckContainer.accountStatus()
            accountStatus = status
            switch status {
            case .available:
                if case .waitingForAccount = phase {
                    phase = .idle
                }
            case .noAccount, .couldNotDetermine:
                phase = .waitingForAccount
            case .restricted:
                phase = .accountRestricted
            case .temporarilyUnavailable:
                phase = .error("iCloud temporarily unavailable.")
            @unknown default:
                phase = .error("Unknown iCloud account status.")
            }
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    private func handle(event: NSPersistentCloudKitContainer.Event) {
        switch event.type {
        case .import:
            phase = event.endDate == nil ? .syncing(activity: .importing) : .idle
        case .export:
            phase = event.endDate == nil ? .syncing(activity: .exporting) : .idle
        case .setup:
            phase = event.endDate == nil ? .syncing(activity: .setup) : .idle
        @unknown default:
            break
        }

        if let error = event.error {
            phase = .error(error.localizedDescription)
        } else if let endDate = event.endDate {
            lastCompletionDate = endDate
            if case .syncing = phase {
                phase = .idle
            }
        }
    }

    private func markRemoteChange() {
        lastCompletionDate = Date()
        if case .syncing = phase {
            phase = .idle
        }
    }
}
