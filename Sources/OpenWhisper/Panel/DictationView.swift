import SwiftUI

struct DictationView: View {
    @ObservedObject var model: AppModel
    var openTrayMenu: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch model.state {
            case .recording:
                recordingBody
            case .transcribing:
                transcribingBody
            case .failed(let reason):
                failedBody(reason)
            case .idle:
                EmptyView()
            }
        }
        .padding(22)
        .frame(width: 380)
        .background(cardColor.opacity(AppSettings.panelOpacity), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var recordingBody: some View {
        VStack(spacing: 14) {
            if case .recording(let startedAt) = model.state {
                header(title: model.livePolishOn ? "Gravando · IA" : "Gravando") {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(formatElapsed(since: startedAt))
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Waveform(accent: accentColor, samples: model.isPaused ? nil : model.levelSamples, muted: model.isPaused)
            transcriptBox
            if model.livePolishOn {
                livePolishBox
            }
            controls(showsFinish: true)
        }
    }

    /// Live IA preview: polished stable sentences below the raw transcript.
    /// Closed sentences go immediately; unpunctuated speech follows after a
    /// short pause. The copy icon grabs the polished-so-far text without
    /// closing — Finalizar still copies the original.
    private var livePolishBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Com IA ✨")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentColor)
                if model.livePolishActive {
                    ProgressView().controlSize(.mini)
                }
                Spacer()
                Button(action: model.copyLivePolished) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(model.livePolishedText.isEmpty ? .secondary.opacity(0.4) : accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .disabled(model.livePolishedText.isEmpty)
                .help("Copiar texto com IA")
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.livePolishedText.isEmpty ? "Aguardando primeira frase…" : model.livePolishedText)
                        .foregroundStyle(model.livePolishedText.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear
                        .frame(height: 1)
                        .id("livepolish-bottom")
                }
                .scrollIndicators(.visible)
                .onChange(of: model.livePolishedText) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("livepolish-bottom", anchor: .bottom)
                    }
                }
            }
            if let livePolishError = model.livePolishError {
                Text(livePolishError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 140)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(fieldColor.opacity(min(1, AppSettings.panelOpacity + 0.06)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accentColor.opacity(0.6), lineWidth: 1.5)
        )
    }

    private var transcribingBody: some View {
        VStack(spacing: 14) {
            header(title: "Transcrevendo…") {
                ProgressView().controlSize(.small)
            }
            Waveform(accent: accentColor, samples: nil, muted: true)
            transcriptBox
            controls(showsFinish: false)
        }
    }

    private func failedBody(_ reason: FailureReason) -> some View {
        VStack(spacing: 14) {
            Image(systemName: heroSymbolName(for: reason))
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.orange)
                .padding(.top, 4)
            Text(message(for: reason))
                .font(.system(size: 16, weight: .semibold))
                .multilineTextAlignment(.center)
            if reason == .permissionDenied {
                Button("Abrir Ajustes de Acessibilidade") {
                    CGEventAutoPasteService.promptPermission()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.callout)
            }
            controls(showsFinish: false)
        }
    }

    private func header(title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 9) {
            if title == "Gravando" {
                Circle().fill(Color.red).frame(width: 11, height: 11).modifier(Pulsing())
            }
            Text(title).font(.system(size: 17, weight: .bold))
            Spacer()
            trailing()
        }
    }

    private var transcriptBox: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(model.liveTranscript.isEmpty ? "Fale alguma coisa…" : model.liveTranscript)
                    .foregroundStyle(model.liveTranscript.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear
                    .frame(height: 1)
                    .id("transcript-bottom")
            }
            .scrollIndicators(.visible)
            .onChange(of: model.liveTranscript) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("transcript-bottom", anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88, maxHeight: 180)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(fieldColor.opacity(min(1, AppSettings.panelOpacity + 0.06)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private func controls(showsFinish: Bool) -> some View {
        HStack(spacing: 10) {
            if let openTrayMenu {
                Button {
                    if case .recording = model.state, !model.isPaused {
                        model.togglePause()
                    }
                    openTrayMenu()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(borderColor, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Menu e configurações")
            }
            if showsFinish {
                Button(action: model.togglePause) {
                    Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 31)
                        .padding(.vertical, 9)
                        .background(Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(borderColor, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(model.isPaused ? "Retomar" : "Pausar")
            }
            Spacer()
            Button(action: model.cancel) {
                Text(cancelTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(borderColor, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            if showsFinish {
                Button(action: model.finish) {
                    Text("Finalizar")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 9)
                        .background(accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var cancelTitle: String {
        if case .failed = model.state { return "Fechar" }
        return "Cancelar"
    }

    private func heroSymbolName(for reason: FailureReason) -> String {
        switch reason {
        case .noSpeech: "waveform.slash"
        case .permissionDenied: "lock.shield"
        default: "exclamationmark.triangle.fill"
        }
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

    private var isDark: Bool { colorScheme == .dark }

    private var cardColor: Color {
        isDark ? Color(red: 0.145, green: 0.118, blue: 0.208) : .white
    }

    private var fieldColor: Color {
        isDark ? Color(red: 0.118, green: 0.094, blue: 0.173) : Color(red: 0.968, green: 0.961, blue: 0.988)
    }

    private var borderColor: Color {
        isDark ? Color(red: 0.243, green: 0.208, blue: 0.333) : Color(red: 0.906, green: 0.886, blue: 0.957)
    }

    private var accentColor: Color {
        isDark ? Color(red: 0.647, green: 0.545, blue: 0.980) : Color(red: 0.427, green: 0.157, blue: 0.851)
    }
}

struct Waveform: View {
    let accent: Color
    var samples: [Double]? = nil
    var muted = false

    private let bars = 12
    private let staticPattern: [CGFloat] = [16, 27, 38, 22, 39, 28, 20, 34, 24, 38, 18, 32]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<bars, id: \.self) { i in
                Capsule()
                    .fill(accent.opacity(muted ? 0.4 : 1))
                    .frame(width: 4, height: height(for: i))
                    .animation(.easeOut(duration: 0.12), value: samples)
            }
        }
        .frame(height: 40)
    }

    private func height(for i: Int) -> CGFloat {
        if let samples, samples.count == bars {
            return max(6, CGFloat(samples[i]) * 38)
        }
        return staticPattern[i % staticPattern.count]
    }
}

struct Pulsing: ViewModifier {
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(dimmed ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: dimmed)
            .onAppear { dimmed = true }
    }
}
