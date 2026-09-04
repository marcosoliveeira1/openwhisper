import SwiftUI

struct DictationView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if showsTranscript {
                ScrollView {
                    Text(model.liveTranscript.isEmpty ? "Fale algo…" : model.liveTranscript)
                        .foregroundStyle(model.liveTranscript.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 160)
            }
            controls
        }
        .padding(16)
        .frame(width: 380)
    }

    @ViewBuilder private var header: some View {
        switch model.state {
        case .recording(let startedAt):
            HStack {
                Circle().fill(.red).frame(width: 9, height: 9)
                Text("Gravando").font(.headline)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(formatElapsed(since: startedAt))
                        .font(.system(.headline, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        case .transcribing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Transcrevendo…").font(.headline)
                Spacer()
            }
        case .failed(let reason):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(message(for: reason)).font(.headline)
                }
                if reason == .permissionDenied {
                    Button("Abrir Ajustes") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        case .idle:
            EmptyView()
        }
    }

    private var showsTranscript: Bool {
        switch model.state {
        case .recording, .transcribing: true
        case .failed, .idle: false
        }
    }

    @ViewBuilder private var controls: some View {
        HStack {
            Spacer()
            Button(action: model.cancel) {
                Text(cancelTitle)
            }
            .keyboardShortcut(.cancelAction)
            if case .failed = model.state {} else {
                Button(action: model.finish) {
                    Text("Finalizar")
                        .padding(.horizontal, 8)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var cancelTitle: String {
        if case .failed = model.state { return "Fechar" }
        return "Cancelar"
    }

    private func message(for reason: FailureReason) -> String {
        switch reason {
        case .noSpeech: "Nenhuma fala detectada"
        case .permissionDenied: "Permissão de microfone ou reconhecimento de fala negada"
        case .recognitionUnavailable: "Reconhecimento de fala indisponível neste momento"
        case .engineError(let detail): "Erro na transcrição: \(detail)"
        }
    }

    private func formatElapsed(since date: Date) -> String {
        let interval = max(0, Int(Date().timeIntervalSince(date)))
        return String(format: "%02d:%02d", interval / 60, interval % 60)
    }
}
