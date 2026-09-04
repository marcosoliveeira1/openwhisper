import SwiftUI

struct DictationView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            heroIcon
            header
            if showsTranscript {
                ScrollView {
                    Text(model.liveTranscript.isEmpty ? "Fale algo…" : model.liveTranscript)
                        .foregroundStyle(model.liveTranscript.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 160)
            }
            if showsPermissionButton {
                Button("Abrir Ajustes") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.large)
            }
            controls
        }
        .padding(20)
        .frame(width: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder private var heroIcon: some View {
        Group {
            switch model.state {
            case .recording:
                Image(systemName: "mic.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.red)
            case .transcribing:
                Image(systemName: "waveform")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.primary)
            case .failed(let reason):
                Image(systemName: heroSymbolName(for: reason))
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.orange)
            case .idle:
                EmptyView()
            }
        }
        .frame(height: 48)
    }

    private func heroSymbolName(for reason: FailureReason) -> String {
        switch reason {
        case .noSpeech: "waveform.slash"
        default: "exclamationmark.triangle.fill"
        }
    }

    @ViewBuilder private var header: some View {
        switch model.state {
        case .recording(let startedAt):
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 12, height: 12)
                Text("Gravando").font(.title3.bold())
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(formatElapsed(since: startedAt))
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        case .transcribing:
            Text("Transcrevendo…").font(.title3.bold())
        case .failed(let reason):
            Text(message(for: reason))
                .font(.title3)
                .multilineTextAlignment(.center)
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

    private var showsPermissionButton: Bool {
        if case .failed(.permissionDenied) = model.state { return true }
        return false
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 12) {
            Spacer()
            Button(action: model.cancel) {
                Text(cancelTitle)
                    .padding(.horizontal, 8)
            }
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)
            if case .failed = model.state {} else {
                Button(action: model.finish) {
                    Text("Finalizar")
                        .padding(.horizontal, 8)
                }
                .controlSize(.large)
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
