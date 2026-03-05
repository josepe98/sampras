import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            if let path = Bundle.main.path(forResource: "sampras_logo", ofType: "jpg"),
               let nsImage = NSImage(contentsOfFile: path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
                    .padding(.top, 28)
            }

            Text("Sampras")
                .font(.title2)
                .fontWeight(.bold)

            Text("Version 1.3")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            Text("Local server monitor & launcher")
                .foregroundStyle(.secondary)
                .font(.caption)

            Text("© 2026 Erik Josephson")
                .foregroundStyle(.secondary)
                .font(.caption)

            Text("Developed with Claude (Anthropic)")
                .foregroundStyle(.tertiary)
                .font(.caption2)

            Spacer()
        }
        .frame(width: 300, height: 240)
    }
}
