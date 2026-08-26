import SwiftUI
import TalkyCore

struct DictationView: View {
    @StateObject private var model = DictationModel.shared

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Text("Talky")
                    .font(.title2.bold())
                Spacer()
                providerPicker
            }

            Spacer()

            transcriptArea

            Spacer()

            recordButton

            Text(statusLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var providerPicker: some View {
        Menu {
            ForEach(model.config.cleanup.providers, id: \.id) { provider in
                Button {
                    model.selectProvider(provider.id)
                } label: {
                    if provider.id == model.activeProviderID {
                        Label(provider.id, systemImage: "checkmark")
                    } else {
                        Text(provider.id)
                    }
                }
            }
        } label: {
            Label(model.activeProviderID, systemImage: "sparkles")
                .font(.footnote)
        }
    }

    private var transcriptArea: some View {
        ScrollView {
            if model.state == .recording {
                Text(model.liveText.isEmpty ? "Listening…" : model.liveText)
                    .foregroundStyle(model.liveText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !model.result.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.result)
                        .textSelection(.enabled)
                    if model.copied {
                        Label("Copied — long-press to paste anywhere", systemImage: "doc.on.clipboard")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Tap the mic, or press your Action button.")
                    .foregroundStyle(.secondary)
            }
            if let error = model.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
        }
        .frame(maxHeight: 320)
    }

    private var recordButton: some View {
        Button {
            model.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(model.state == .recording ? Color.red : Color.accentColor)
                    .frame(width: 84, height: 84)
                Image(systemName: model.state == .recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.state == .processing)
    }

    private var statusLine: String {
        switch model.state {
        case .idle: return "ready"
        case .recording: return "listening — tap to finish"
        case .processing: return "cleaning up…"
        }
    }
}
