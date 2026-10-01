# STATE.md — OpenWhisper

## Decisions

| ID | Date | Decision | Status |
| -- | ---- | -------- | ------ |
| AD-001 | 2026-09-04 | Build: SPM + Makefile (bundle .app manual, ad-hoc codesign). Sem projeto Xcode, sem XcodeGen. | active |
| AD-002 | 2026-09-04 | Atalho global via Carbon `RegisterEventHotKey`, default ⌘⇧G. Conflito com Finder "Ir para a Pasta" aceito pelo usuário. | active |
| AD-003 | 2026-09-04 | Zero dependências de terceiros em runtime; efeitos de sistema (speech, clipboard) atrás de protocolos para testabilidade via `swift test` (Swift Testing). | active |
| AD-004 | 2026-09-04 | Bundle ID `br.marcos.openwhisper`; persistência em JSON em `~/Library/Application Support/OpenWhisper/`; Speech pt-BR com feature-detect on-device (fallback server-based). | active |
| AD-005 | 2026-09-04 | Painel ABRE COM FOCO (ativa o app, key window) — reversão da premissa "nonactivating" a pedido do usuário; Enter finaliza, Esc cancela via keyboard shortcuts. Motivação: receber teclado (Enter/Esc) sem clique prévio. | active |
| AD-006 | 2026-09-04 | Atalho global e limite de histórico configuráveis via UI de Configurações (janela própria); persistência em UserDefaults (keys `hotKeyCode`, `hotKeyModifiers`, `historyLimit`). Atalho requer ≥1 modificador. Supersedes parte do P2 (OW-12) e OW-09 fixo em 50. | active |
| AD-007 | 2026-09-04 | Bug do "Limpar histórico" era booleano invertido (`isEnabled = !contains`) — lógica de habilitação movida para o `HistoryMenuBuilder` (código puro testável) e aplicada pelo StatusBarController. | resolved |
| AD-008 | 2026-09-04 | Auto-paste ao finalizar (reversão da exclusão de escopo original, a pedido do usuário): texto é copiado E colado via CGEvent ⌘V no app que estava em foco ao INICIAR o ditado (pid capturado no start, foco restaurado também no Cancelar). Requer permissão de Acessibilidade — prompt no primeiro finish sem grant; cópia permanece como fallback. Toggle em Configurações (default ON, key `autoPasteEnabled`). | active |
| AD-009 | 2026-09-04 | Pausa na fala encerrava a task on-device (endpointing/erro por silêncio) e congelava partials → Finalizar falhava com noSpeech e nada ia pro histórico. Fix: `SegmentTranscript` (tipo puro testável) acumula prefixo finalizado; task/engine/tap são reiniciados de forma transparente em isFinal, erro de task ou troca de rota de áudio, preservando o texto. Waveform usa níveis RMS reais do tap; botões do painel sem bezel padrão do macOS. | active |
| AD-010 | 2026-09-30 | Limpeza com IA sob demanda (code-switch PT/EN): protocolo `TextPolisher` (mockável) + `FoundationModelsPolisher` (Apple Intelligence on-device, grátis, privado, zero third-party); requer macOS 26 + Apple Intelligence ativo — `#if canImport` + `#available` com nil em macOS 15. v2 (redesign a pedido do usuário): sem polish in-place na gravação; `finish()` para de copiar e abre tela REVIEWING (fica aberta, nada copiado); **Finalizar** copia o original e fecha (+auto-paste); **✨ Copiar com IA** roda polish em batches de ≤2000 chars (`PolishPrompt.chunk`, 1 call por chunk, sequencial), exibe bloco corrigido abaixo, copia + salva no histórico, tela continua aberta com **Fechar** no lugar; **Cancelar** descarta de qualquer estado. Escopo anterior "correção por IA via API OpenAI" substituído por on-device (sem API key). | active |

## Handoff

**In-flight:** Gateways de IA (AD-011): `AIProvider` (apple/openRouter/groq/openCode) + `HTTPChatPolisher` (`POST {base}/chat/completions`, temperature 0, reusa prompt/clean/isPlausible) + `RoutingPolisher` (troca sem restart; leitura via `GatewayStore` nonisolated); Settings → IA com picker + baseURL/chave/modelo por provider (OpenCode sem preset). 85/85 testes verdes (GatewayTests serializada — suites paralelas corriam race em UserDefaults/handler), instalado em /Applications. Conhecido: `swift test` falha ~70% das vezes com TestingMacros plugin missing (flake do CLT 27/SDK26.5, reproduz em pacote mínimo; retry até verde). Chaves em UserDefaults plaintext (melhorar p/ Keychain depois?).
**Next step:** UAT com gateway real (Groq/OpenRouter: colar chave em Configurações → IA, falar e ver latência/qualidade vs Apple).
