import SwiftUI

struct RecordingsLibraryView: View {
    @ObservedObject var coordinator: RecordingCoordinator

    @State private var recordings: [URL] = []
    @State private var selectedRecording: URL?
    @State private var pendingDeleteURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recordings")
                    .font(.title2.weight(.semibold))

                Spacer()

                Button("Refresh") {
                    reloadRecordings()
                }
                .buttonStyle(.bordered)

                Button("Open Folder") {
                    openRecordingsFolder()
                }
                .buttonStyle(.bordered)
            }

            if recordings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "film")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("No recordings yet")
                        .font(.headline)
                    Text("Start a capture to see recordings here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedRecording) {
                    ForEach(recordings, id: \.self) { recordingURL in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recordingURL.lastPathComponent)
                                    .font(.body)
                                    .lineLimit(1)

                                Text(relativeDateText(for: recordingURL))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("Preview") {
                                coordinator.openFile(at: recordingURL)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Reveal") {
                                coordinator.revealFile(at: recordingURL)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Delete") {
                                deleteRecording(recordingURL)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.red)
                        }
                        .tag(recordingURL)
                    }
                }
            }
        }
        .padding(20)
        .task {
            reloadRecordings()
        }
        .alert("Delete Recording Permanently?", isPresented: Binding(
            get: { pendingDeleteURL != nil },
            set: { if !$0 { pendingDeleteURL = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let pendingDeleteURL {
                    coordinator.deleteRecording(at: pendingDeleteURL)
                    reloadRecordings()
                }
                self.pendingDeleteURL = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteURL = nil
            }
        } message: {
            Text("This will permanently delete the video and related project files.")
        }
    }

    private func reloadRecordings() {
        recordings = coordinator.availableRecordingFiles()
            .sorted(by: { lhs, rhs in
                (modificationDate(for: lhs) ?? .distantPast) > (modificationDate(for: rhs) ?? .distantPast)
            })

        if let selectedRecording,
           !recordings.contains(selectedRecording) {
            self.selectedRecording = nil
        }
    }

    private func deleteRecording(_ recordingURL: URL) {
        pendingDeleteURL = recordingURL
    }

    private func openRecordingsFolder() {
        coordinator.openRecordingsFolder()
    }

    private func relativeDateText(for fileURL: URL) -> String {
        guard let date = modificationDate(for: fileURL) else {
            return "Unknown date"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func modificationDate(for fileURL: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date) ?? nil
    }
}
