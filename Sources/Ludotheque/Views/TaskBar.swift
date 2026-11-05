// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI

/// Detailed list of background jobs (popover of the top progress bar).
struct TaskList: View {
    @ObservedObject private var center = TaskCenter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tâches en cours").font(.headline)
            if center.jobs.isEmpty { Text("Aucune tâche.").foregroundStyle(.secondary) }
            ForEach(center.jobs) { job in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(job.title).font(.callout.weight(.semibold))
                        Spacer()
                        if job.total > 0 {
                            Text("\(job.done)/\(job.total) · \(Int((job.fraction ?? 0) * 100)) %").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        if center.isRunning(job.id) {
                            Button { center.cancel(job.id) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.plain).help("Arrêter")
                        }
                    }
                    if let f = job.fraction { ProgressView(value: f) } else { ProgressView().progressViewStyle(.linear) }
                    HStack {
                        if !job.detail.isEmpty { Text(job.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        Spacer()
                        if let eta = job.eta {
                            Text("≈ \(eta < 60 ? "\(Int(eta)) s" : "\(Int(eta / 60)) min") restantes").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
    }
}
