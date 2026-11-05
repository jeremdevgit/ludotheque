// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI

/// Grey placeholder shapes shown while content loads, in place of a spinner:
/// the layout is already in place, so the view feels ready immediately.
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var radius: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.secondary.opacity(0.18))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// Gentle pulse shared by all skeletons (one animation, no per-frame work in the views).
/// (`phaseAnimator`: no @State, which this toolchain's SwiftUI macros don't support.)
struct SkeletonPulse: ViewModifier {
    func body(content: Content) -> some View {
        content
            .phaseAnimator([1.0, 0.45]) { view, opacity in view.opacity(opacity) } animation: { _ in .easeInOut(duration: 0.9) }
            .accessibilityLabel("Chargement")
    }
}

extension View {
    func skeletonPulse() -> some View { modifier(SkeletonPulse()) }
}

/// A few lines of text (paragraph placeholder).
struct SkeletonLines: View {
    var count = 4
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                // Last line shorter, like real text.
                if i == count - 1 { SkeletonBlock(width: 160) } else { SkeletonBlock() }
            }
        }
        .skeletonPulse()
    }
}

/// Table rows placeholder.
struct SkeletonRows: View {
    var count = 6
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 12) {
                    SkeletonBlock(width: 140); SkeletonBlock(); SkeletonBlock(width: 70)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .skeletonPulse()
    }
}
