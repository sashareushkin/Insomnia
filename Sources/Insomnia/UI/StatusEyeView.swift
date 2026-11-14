import SwiftUI

/// The eye opens for a session or a display assertion. The sun distinguishes
/// Screen On even when the menu bar is compact, without relying on colour.
struct StatusEyeView: View {
    let isRunning: Bool
    let isScreenOn: Bool
    let reduceMotion: Bool

    var body: some View {
        EyeMarkView(isRunning: isRunning || isScreenOn, reduceMotion: reduceMotion)
            .frame(width: 20, height: 20)
            .overlay(alignment: .bottomTrailing) {
                if isScreenOn {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.primary)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
            }
    }
}
