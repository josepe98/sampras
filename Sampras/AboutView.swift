import SwiftUI

struct AboutView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            if let nsImage = logoImage(for: colorScheme) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
                    .padding(.top, 28)
            }

            Text("Sampras")
                .font(.title2)
                .fontWeight(.bold)

            Text("Version 1.8")
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

    private func logoImage(for scheme: ColorScheme) -> NSImage? {
        if scheme == .dark {
            if let path = Bundle.main.path(forResource: "sampras_logo_dark", ofType: "png") {
                return NSImage(contentsOfFile: path)
            }
        }
        if let path = Bundle.main.path(forResource: "sampras_logo", ofType: "jpg") {
            return NSImage(contentsOfFile: path)
        }
        return nil
    }
}
