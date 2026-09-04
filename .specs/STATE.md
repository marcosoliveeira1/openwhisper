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

## Handoff

**In-flight:** Nenhum — OpenWhisper MVP completo e validado (Verifier PASS, commit c621d5f).
**Next step:** UAT interativo com o usuário (voz real: ⌘⇧G, transcrição pt-BR, auto-copy, histórico, Cancelar). Depois: próxima feature = correção por IA via API compatível OpenAI (spec própria).
