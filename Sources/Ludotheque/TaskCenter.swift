// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation

/// Long-running jobs (performance search, achievements, prices…) live here instead of in views,
/// so they keep running when the user switches tabs. The top bar shows their detailed progress.
@MainActor
final class TaskCenter: ObservableObject {
    static let shared = TaskCenter()

    struct Job: Identifiable, Equatable {
        let id: String
        let title: String
        var detail = ""
        var done = 0
        var total = 0              // 0 = indeterminate
        let started = Date()

        var fraction: Double? { total > 0 ? min(1, Double(done) / Double(total)) : nil }
        /// Remaining time estimate once a few steps are done.
        var eta: TimeInterval? {
            guard total > 5, done >= 3, done < total else { return nil }
            return Date().timeIntervalSince(started) / Double(done) * Double(total - done)
        }
    }

    @Published private(set) var jobs: [Job] = []
    private var tasks: [String: Task<Void, Never>] = [:]

    func isRunning(_ id: String) -> Bool { tasks[id] != nil }

    /// Starts a job unless one with the same id is already running.
    @discardableResult
    func run(_ id: String, _ title: String, _ work: @escaping @MainActor () async -> Void) -> Bool {
        guard tasks[id] == nil else { return false }
        jobs.append(Job(id: id, title: title))
        tasks[id] = Task { @MainActor in
            await work()
            self.finish(id)
        }
        return true
    }

    /// Runs the job and waits for it (or for the already-running one with the same id).
    func runAndWait(_ id: String, _ title: String, _ work: @escaping @MainActor () async -> Void) async {
        run(id, title, work)
        await tasks[id]?.value
    }

    /// Tracks work driven by the caller (no Task of its own); close it with `end`.
    func begin(_ id: String, _ title: String) {
        guard !jobs.contains(where: { $0.id == id }) else { return }
        jobs.append(Job(id: id, title: title))
    }

    func end(_ id: String) { if tasks[id] == nil { jobs.removeAll { $0.id == id } } }

    func progress(_ id: String, _ done: Int, _ total: Int, _ detail: String? = nil) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].done = done
        jobs[i].total = total
        if let detail { jobs[i].detail = detail }
    }

    func detail(_ id: String, _ text: String) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].detail = text
    }

    func cancel(_ id: String) {
        tasks[id]?.cancel()
        finish(id)
    }

    private func finish(_ id: String) {
        tasks[id] = nil
        jobs.removeAll { $0.id == id }
    }
}
