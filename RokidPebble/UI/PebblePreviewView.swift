import SwiftUI

struct PebblePreviewView: View {
    @ObservedObject var vm: HubViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                watchMockup
                sourcePicker
                buttonHint
            }
            .padding()
        }
    }

    // MARK: - Watch mockup (144×168 style)

    private var watchMockup: some View {
        ZStack {
            // Watch body
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.systemGray6))
                .frame(width: 160, height: 200)
                .shadow(radius: 8)

            // Screen
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black)
                .frame(width: 132, height: 152)

            // Content
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: currentSource?.sourceIcon ?? "antenna.radiowaves.left.and.right")
                        .foregroundColor(.white)
                        .imageScale(.small)
                    Text(currentSource?.sourceName ?? "No source")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Spacer()
                    Text(timeString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(white: 0.6))
                }

                Divider().background(Color.gray)

                Text(currentSource?.line1 ?? "--")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(2)

                if let l2 = currentSource?.line2, !l2.isEmpty {
                    Text(l2)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(white: 0.7))
                        .lineLimit(2)
                }
                if let l3 = currentSource?.line3, !l3.isEmpty {
                    Text(l3)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(white: 0.6))
                        .lineLimit(1)
                }

                Spacer()

                // Connection indicator
                HStack {
                    Circle()
                        .fill(vm.pebble.connectionState == .connected ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    Text(vm.pebble.connectionState == .connected ? "Connected" : "Not connected")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color(white: 0.5))
                }
            }
            .padding(10)
            .frame(width: 132, height: 152)

            // Side buttons
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.systemGray4))
                .frame(width: 6, height: 18)
                .offset(x: 83, y: -40)  // up button

            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.systemGray4))
                .frame(width: 6, height: 24)
                .offset(x: 83, y: 0)   // select button

            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.systemGray4))
                .frame(width: 6, height: 18)
                .offset(x: 83, y: 40)  // down button
        }
        .frame(height: 220)
    }

    // MARK: - Source picker

    private var sourcePicker: some View {
        let sources = vm.activeSources
        return VStack(alignment: .leading, spacing: 8) {
            Text("Pebble source (\(vm.pebbleSourceIndex % max(sources.count,1) + 1) of \(max(sources.count,1)))")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            if sources.isEmpty {
                Text("No active sources — enable in Settings")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                HStack {
                    Button {
                        let n = sources.count
                        vm.pebbleSourceIndex = (vm.pebbleSourceIndex - 1 + n) % n
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.title2)
                    }
                    Spacer()
                    if let src = currentSource {
                        VStack(spacing: 2) {
                            Image(systemName: src.sourceIcon).font(.title3)
                            Text(src.sourceName).font(.subheadline.bold())
                        }
                    }
                    Spacer()
                    Button {
                        let n = sources.count
                        vm.pebbleSourceIndex = (vm.pebbleSourceIndex + 1) % n
                    } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.title2)
                    }
                }
                .padding()
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Button hint

    private var buttonHint: some View {
        GroupBox("Watch Button Controls") {
            VStack(alignment: .leading, spacing: 6) {
                buttonRow("⬆ Up",     "Previous source")
                buttonRow("● Select", "Reserved")
                buttonRow("⬇ Down",   "Next source")
            }
            .font(.subheadline)
        }
    }

    private func buttonRow(_ button: String, _ action: String) -> some View {
        HStack {
            Text(button).foregroundColor(.secondary).frame(width: 80, alignment: .leading)
            Text(action)
        }
    }

    // MARK: - Helpers

    private var currentSource: SourceData? {
        let sources = vm.activeSources
        guard !sources.isEmpty else { return nil }
        return sources[vm.pebbleSourceIndex % sources.count]
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }
}
