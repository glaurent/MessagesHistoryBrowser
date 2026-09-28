//
//  ImportProgressView.swift
//  MessagesHistoryBrowser
//
//  Import progress overlay
//

import SwiftUI

// Publishes a Progress's state to SwiftUI.
//
// A Progress can change thousands of times per second from the import thread
// (one tick per chat row, per contact, plus description changes). Forwarding
// each change to the main thread would flood it with tiny blocks and
// re-render the overlay far more often than the display can show, so changes
// are coalesced: the first one in a window schedules a single main-thread
// refresh that reads the Progress's latest values when it fires.
//
// Meant to be created once per import and kept alive for its duration (see
// ContentViewModel.importProgressObserver), so the KVO subscriptions are set
// up once rather than on every re-render of the hosting view.
final class ObservableProgress: ObservableObject {
    @Published private(set) var fractionCompleted: Double
    @Published private(set) var localizedDescription: String
    @Published private(set) var localizedAdditionalDescription: String

    let progress: Progress

    private var observations = [NSKeyValueObservation]()

    // Where refreshes are published. Main for the UI; injectable for tests.
    private let refreshQueue: DispatchQueue

    // Guards `refreshScheduled`, which is touched from the KVO thread and the refresh queue.
    private let lock = NSLock()
    private var refreshScheduled = false
    private let refreshInterval: TimeInterval = 1.0 / 15   // at most ~15 UI refreshes per second

    init(progress: Progress, refreshQueue: DispatchQueue = .main) {
        self.progress = progress
        self.refreshQueue = refreshQueue
        fractionCompleted = progress.fractionCompleted
        localizedDescription = progress.localizedDescription ?? ""
        localizedAdditionalDescription = progress.localizedAdditionalDescription ?? ""

        observations = [
            progress.observe(\.fractionCompleted) { [weak self] _, _ in self?.scheduleRefresh() },
            progress.observe(\.localizedDescription) { [weak self] _, _ in self?.scheduleRefresh() },
            progress.observe(\.localizedAdditionalDescription) { [weak self] _, _ in self?.scheduleRefresh() },
        ]
    }

    // Called from whatever thread mutates the Progress.
    private func scheduleRefresh() {
        lock.lock()
        let alreadyScheduled = refreshScheduled
        refreshScheduled = true
        lock.unlock()
        guard !alreadyScheduled else { return }

        refreshQueue.asyncAfter(deadline: .now() + refreshInterval) { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            self.refreshScheduled = false
            self.lock.unlock()
            self.refresh()
        }
    }

    // Runs on the refresh queue. Reads the current values, so nothing is lost
    // by coalescing; a change arriving during this call simply schedules the
    // next refresh.
    private func refresh() {
        fractionCompleted = progress.fractionCompleted
        localizedDescription = progress.localizedDescription ?? ""
        localizedAdditionalDescription = progress.localizedAdditionalDescription ?? ""
    }
}


struct ImportProgressView: View {
    @ObservedObject var progressWrapper: ObservableProgress
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView(value: progressWrapper.fractionCompleted) {
                    Text(progressWrapper.localizedDescription.isEmpty ? "Importing..." : progressWrapper.localizedDescription)
                        .font(.headline)
                } currentValueLabel: {
                    if !progressWrapper.localizedAdditionalDescription.isEmpty {
                        Text(progressWrapper.localizedAdditionalDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .progressViewStyle(.linear)
                .frame(width: 300)
                
                Text("\(Int(progressWrapper.fractionCompleted * 100))%")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.background)
                    .shadow(radius: 10)
            )
        }
    }
}
