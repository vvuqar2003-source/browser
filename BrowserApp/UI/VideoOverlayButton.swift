import SwiftUI

struct VideoOverlayButton: View {
    let videoCount: Int
    let onTap: () -> Void

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

                    if videoCount > 0 {
                        Text("\(videoCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
            }
            .scaleEffect(isAnimating && videoCount == 0 ? 1.0 : 1.0)
        }
    }
}
