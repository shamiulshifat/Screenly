import SwiftUI

struct SettingsSheetView: View {
    @ObservedObject var coordinator: RecordingCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var startAtLogin = false
    @State private var showAdvancedControls = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.94), Color.gray.opacity(0.3), Color.black.opacity(0.94)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Circle()
                        .fill(Color.red.opacity(0.92))
                        .frame(width: 16, height: 16)

                    Spacer()

                    Text("Settings")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))

                    Spacer()

                    Button("Feedback") {}
                        .buttonStyle(.plain)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)

                Divider().overlay(Color.white.opacity(0.08))

                VStack(spacing: 12) {
                    settingsRow("Save Location:") {
                        HStack(spacing: 8) {
                            Text(coordinator.saveDirectoryPath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button {
                                coordinator.chooseSaveDirectory()
                            } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    settingsRow("Startup:") {
                        Toggle("Start at login", isOn: $startAtLogin)
                            .toggleStyle(.checkbox)
                    }

                    settingsRow("Start/Pause Recording:") {
                        shortcutPill("⌘ + ⇧ + R / P")
                    }

                    settingsRow("Stop Recording:") {
                        shortcutPill("⌘ + ⇧ + S")
                    }

                    settingsRow("Toggle Camera:") {
                        shortcutPill("⌘ + ⇧ + C")
                    }

                    settingsRow("Toggle Mic:") {
                        shortcutPill("⌘ + ⇧ + M")
                    }

                    settingsRow("Version:") {
                        Text("V1.0.0")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 22)

                Divider().overlay(Color.white.opacity(0.08))

                HStack {
                    Button("Advanced Controls") {
                        showAdvancedControls = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Spacer()

                    Button("OK") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(minWidth: 140)
                }
                .padding(20)
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .sheet(isPresented: $showAdvancedControls) {
            NavigationStack {
                RecordingSetupView(coordinator: coordinator)
                    .navigationTitle("Advanced Controls")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                showAdvancedControls = false
                            }
                        }
                    }
            }
            .frame(minWidth: 980, minHeight: 760)
        }
    }

    private func settingsRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.86))
                .frame(width: 260, alignment: .trailing)

            content()
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func shortcutPill(_ value: String) -> some View {
        Text(value)
            .font(.system(.title3, design: .monospaced).weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
    }
}
