// BrowserApp/BrowserApp/UI/VideoOverlayButton.swift

import SwiftUI

struct VideoOverlayButton: View {
    let videoCount: Int
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var isAnimating = false

    var body: some View {
        Button {
            onTap()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)

                VStack(spacing: 2) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)

                    if videoCount > 1 {
                        Text("\(videoCount)")
                            .font(.caption2)
                            .foregroundColor(.white)
                    }
                }
            }
            .scaleEffect(isAnimating ? 1.1 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    onLongPress()
                }
        )
    }
}
