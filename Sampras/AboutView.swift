import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "network")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .foregroundStyle(.blue)
                .padding(.top, 28)

            Text("Sampras")
                .font(.title2)
                .fontWeight(.bold)

            Text("Version 1.0")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            Text("Local server monitor & launcher")
                .foregroundStyle(.secondary)
                .font(.caption)

            Spacer()
        }
        .frame(width: 300, height: 220)
    }
}
