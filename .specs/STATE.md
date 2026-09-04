# STATE.md — OpenWhisper

## Decisions

| ID | Date | Decision | Status |
| -- | ---- | -------- | ------ |
| AD-001 | 2026-09-04 | Build: SPM + Makefile (bundle .app manual, ad-hoc codesign). Sem projeto Xcode, sem XcodeGen. | active |
| AD-002 | 2026-09-04 | Atalho global via Carbon `RegisterEventHotKey`, default ⌘⇧G. Conflito com Finder "Ir para a Pasta" aceito pelo usuário. | active |
| AD-003 | 2026-09-04 | Zero dependências de terceiros em runtime; efeitos de sistema (speech, clipboard) atrás de protocolos para testabilidade via `swift test` (Swift Testing). | active |
| AD-004 | 2026-09-04 | Bundle ID `br.marcos.openwhisper`; persistência em JSON em `~/Library/Application Support/OpenWhisper/`; Speech pt-BR com feature-detect on-device (fallback server-based). | active |

## Handoff

**In-flight:** Nenhum — OpenWhisper MVP completo e validado (Verifier PASS, commit c621d5f).
**Next step:** UAT interativo com o usuário (voz real: ⌘⇧G, transcrição pt-BR, auto-copy, histórico, Cancelar). Depois: próxima feature = correção por IA via API compatível OpenAI (spec própria).
