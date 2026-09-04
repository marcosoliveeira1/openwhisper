# OpenWhisper MVP Tasks

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill: **activate it by name and follow its Execute flow and Critical Rules.** Do not search for skill files by filesystem path. The skill is the source of truth for the full flow (per-task cycle, sub-agent delegation, adequacy review, Verifier, discrimination sensor).

**If the skill cannot be activated, STOP and tell the user — do not proceed without it.**

---

**Design**: `.specs/features/openwhisper-mvp/design.md`
**Status**: Draft

---

## Test Coverage Matrix

> Generated from codebase (greenfield — no existing tests) and spec — confirm before Execute. Guidelines found: none — strong defaults applied.

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| ---------- | ------------------ | -------------------- | ---------------- | ----------- |
| Domain logic (`AppModel`, `TranscriptionStore`, `HistoryMenuBuilder`) | unit (Swift Testing) | Todas as transições de estado 1:1 com ACs OW-04..10; todos os edge cases da spec (vazio, toggle, falha) | `Tests/OpenWhisperTests/*.swift` | `swift test` |
| System integration (Speech, hotkey, NSPanel, NSStatusItem, AppDelegate wiring) | none | Build gate + checklist manual de UAT por AC (mic/voz não automatizável headless) | — | `swift build && make app` |

## Parallelism Assessment

> Generated from codebase — confirm before Execute.

| Test Type | Parallel-Safe? | Isolation Model | Evidence |
| --------- | -------------- | --------------- | -------- |
| unit | Yes | `TranscriptionStore` recebe URL de arquivo temp única por teste; `AppModel` usa mocks injetados sem estado global | Design: dependências via protocolos, sem singletons |

## Gate Check Commands

> Generated from codebase — confirm before Execute.

| Gate Level | When to Use | Command |
| ---------- | ----------- | ------- |
| Quick | Após tasks com unit tests | `swift test` |
| Build | Após tasks sem testes (system layer) ou config/infra | `swift build && make app` |
| Full | Fechamento de fase / feature | `swift test && swift build -c release && make app` |

---

## Execution Plan

### Phase 1: Foundation (Sequential)

```
T1 → T2 → T3
```

### Phase 2: Core Implementation (Parallel OK)

```
T3 complete, then:
  ├── T4 [P]
  ├── T5 (dep: T4)
  ├── T6 [P]
  └── T7 [P]
```

### Phase 3: Integration (Sequential)

```
T4..T7 complete, then:
  T8 → T9
```

---

## Task Breakdown

### T1: Scaffold do projeto e app tray mínimo

**What**: Package.swift (executable `OpenWhisper` + test target), Info.plist (`LSUIElement`, usage descriptions mic/speech, bundle ID `br.marcos.openwhisper`), Makefile (`app` monta .app + ad-hoc codesign; `run`; `clean`), `main.swift` + `AppDelegate` mínimo com `NSStatusItem` placeholder e app sem ícone no Dock.
**Where**: `Package.swift`, `Info.plist`, `Makefile`, `Sources/OpenWhisper/main.swift`, `Sources/OpenWhisper/AppDelegate.swift`
**Depends on**: None
**Reuses**: —
**Requirement**: OW-02 (parcial: tray-only)

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] `swift build` compila sem warnings
- [ ] `make app` produz `build/OpenWhisper.app` assinado ad-hoc
- [ ] App abre e mostra item "OpenWhisper" no menu bar; NADA no Dock
- [ ] `swift test` roda (suíte vazia ok)

**Tests**: none (infra layer — build gate)
**Gate**: build

---

### T2: Modelo Transcription + TranscriptionStore

**What**: Struct `Transcription` (Codable) e actor `TranscriptionStore` com `add` (cap 50, descarta mais antiga), `all` (mais recente primeiro), `clear`, persistência JSON em URL injetável (default: Application Support).
**Where**: `Sources/OpenWhisper/TranscriptionStore.swift`
**Depends on**: T1
**Reuses**: —
**Requirement**: OW-09, OW-10

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] Cap de 50 respeitado (51ª inserção descarta a mais antiga)
- [ ] Persist/load round-trip no arquivo JSON
- [ ] `clear()` zera memória e arquivo
- [ ] Gate check passes: `swift test`
- [ ] Test count: ≥ 5 tests pass (cap, ordering, round-trip, clear, empty-file reload)

**Tests**: unit
**Gate**: quick

---

### T3: DictationService protocol + AppleSpeechService

**What**: Protocolo `DictationService` (`start/onPartial/finish/cancel`) e implementação `AppleSpeechService`: `SFSpeechRecognizer(pt-BR)`, feature-detect on-device, `AVAudioEngine` input tap → `SFSpeechAudioBufferRecognitionRequest`, autorização mic+speech em runtime, mapeamento de erros do design, `finish()` devolve partials em falha de task.
**Where**: `Sources/OpenWhisper/Speech/DictationService.swift`, `Sources/OpenWhisper/Speech/AppleSpeechService.swift`
**Depends on**: T1
**Reuses**: —
**Requirement**: OW-01, OW-03, OW-04 (base de transcrição)

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] `swift build` compila
- [ ] Ciclo start→finish retorna String? sem crash (verificação manual com debug no app ou via harness temporário)
- [ ] Erros de autorização mapeiam para `FailureReason` do design
- [ ] Gate check passes: `swift build && make app`

**Tests**: none (system layer — build gate + UAT em T8)
**Gate**: build

---

### T4: AppModel (máquina de estados) + Clipboard

**What**: `AppModel` ObservableObject com `DictationState`, `toggle/finish/cancel/copyToClipboard`, regras: toggle com painel aberto = finish; transcribing ignora toggle; transcript vazio = zero side effects + estado de mensagem; finish copia→persiste→fecha; cancel não toca clipboard nem store. Protocolo `Clipboard` + `NSPasteboardClipboard`.
**Where**: `Sources/OpenWhisper/AppModel.swift`, `Sources/OpenWhisper/Clipboard.swift`
**Depends on**: T2, T3
**Reuses**: T2 `TranscriptionStore`, T3 `DictationService` (protocolo)
**Requirement**: OW-04, OW-05, OW-06, OW-01 (toggle)

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] Todos os caminhos do design cobertos por testes com mocks (mock DictationService/Clipboard/Store)
- [ ] Gate check passes: `swift test`
- [ ] Test count: ≥ 8 tests pass (toggle-open, toggle-finish, cancel-zero-effects, empty-transcript, transcribing-ignores-toggle, finish-persists+copies, copy-from-history, failure-state)

**Tests**: unit
**Gate**: quick

---

### T5: Painel flutuante (NSPanel + SwiftUI)

**What**: `DictationPanelController` (NSPanel `.nonactivatingPanel`/`.borderless`, level `.floating`, `canJoinAllSpaces`) + `DictationView`: indicador de gravação + timer, live text (partials), botões Finalizar/Cancelar, Esc = cancelar, estado `.failed` com mensagem inline e botão "Abrir Ajustes".
**Where**: `Sources/OpenWhisper/Panel/DictationPanelController.swift`, `Sources/OpenWhisper/Panel/DictationView.swift`
**Depends on**: T4
**Reuses**: T4 `AppModel` (EnvironmentObject)
**Requirement**: OW-01, OW-02, OW-03, OW-11

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] Painel aparece sobre janelas de outros apps sem ativar o app de trás
- [ ] Partials aparecem em tempo real durante gravação
- [ ] Esc dispara cancel; botões disparam finish/cancel no AppModel
- [ ] Permissão negada mostra erro + "Abrir Ajustes"
- [ ] Gate check passes: `swift build && make app`

**Tests**: none (UI layer — build gate + UAT em T8)
**Gate**: build

---

### T6: StatusBarController + HistoryMenuBuilder

**What**: `HistoryMenuBuilder` (lógica pura: truncar label a 60 chars, tooltip completo, mais recente primeiro, vazio → "Sem transcrições" desabilitado, itens fixos Limpar histórico/Sair) e `StatusBarController` que renderiza o menu, copia no click, reconstrói quando o store muda.
**Where**: `Sources/OpenWhisper/StatusBar/HistoryMenuBuilder.swift`, `Sources/OpenWhisper/StatusBar/StatusBarController.swift`
**Depends on**: T2, T4
**Reuses**: T2 store, T4 `AppModel.copyToClipboard`
**Requirement**: OW-07, OW-08

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] Builder puro testado (truncamento 60+tooltip, ordenação, estado vazio, itens fixos presentes)
- [ ] Click numa entrada copia texto completo
- [ ] Gate check passes: `swift test`
- [ ] Test count: ≥ 4 tests pass (truncation, ordering, empty-state, fixed-items)

**Tests**: unit
**Gate**: quick

---

### T7: HotKeyController (⌘⇧G global)

**What**: Registro Carbon `RegisterEventHotKey` para ⌘⇧G com handler injetável; `start/stop`; keycode/modifiers como constantes nomeadas.
**Where**: `Sources/OpenWhisper/HotKeyController.swift`
**Depends on**: T1
**Reuses**: —
**Requirement**: OW-01

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] Dispara handler ao pressionar ⌘⇧G com app em background (verificação manual via debug print)
- [ ] Repetir o atalho dispara novamente (registro não consome repeat)
- [ ] Gate check passes: `swift build && make app`

**Tests**: none (system layer — build gate + UAT em T8)
**Gate**: build

---

### T8: Integração completa (AppDelegate wiring + fluxo end-to-end)

**What**: Composição final no AppDelegate: HotKey→AppModel.toggle; painel reflete estado; StatusBarController atualiza ao persistir; request de permissões no primeiro ditado; fluxo completo ⌘⇧G→fala→Finalizar→⌘V; Cancelar/Esc; histórico entre restarts.
**Where**: `Sources/OpenWhisper/AppDelegate.swift` (modify)
**Depends on**: T4, T5, T6, T7
**Reuses**: todos os componentes
**Requirement**: OW-01..OW-10 (integração)

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] Checklist UAT do spec executa sem falhas (cada AC testado manualmente)
- [ ] Histórico sobrevive a quit+relaunch
- [ ] Gate check passes: `swift test && make app`

**Tests**: none (integration manual — cobertura automatizada já garantida em T2/T4/T6)
**Gate**: full

---

### T9: Edge cases e polimento final

**What**: Edge cases da spec: transcript vazio ("Nenhuma fala detectada", sem copiar), falha de reconhecimento (partials entregues / erro inline), desconexão de áudio/sleep (finish gracioso), toggle durante transcribing ignorado, menu vazio desabilitado. Ajustes finais de layout/leveza.
**Where**: `Sources/OpenWhisper/AppModel.swift`, `Sources/OpenWhisper/Speech/AppleSpeechService.swift` (modify)
**Depends on**: T8
**Reuses**: tudo
**Requirement**: Edge Cases da spec (OW-01..10)

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] Cada edge case da spec tem caminho de código + verificação (unit onde mockável)
- [ ] Test count: ≥ 3 novos tests pass (empty-finish, partial-on-error, audio-interrupt via mocks)
- [ ] Gate check passes: `swift test && swift build -c release && make app`

**Tests**: unit
**Gate**: full

---

## Parallel Execution Map

```
Phase 1 (Sequential):
  T1 ──→ T2 ──→ T3

Phase 2 (Mixed):
  T3 complete, then:
    ├── T4 [P]
    ├── T6 [P]   } T6 depends on T2+T4 (AppModel) → after T4
    ├── T7 [P]
    └── T5 (after T4)

Phase 3 (Sequential):
  T4..T7 complete, then:
    T8 ──→ T9
```

Nota: T6 usa `AppModel.copyToClipboard` (T4) → depende de T4 na prática; marcado `[P]` relativo a T5/T7 (sem dependência entre eles). T5 depende de T4.

---

## Task Granularity Check

| Task | Scope | Status |
| ---- | ----- | ------ |
| T1: Scaffold + tray mínimo | 1 setup coeso (5 arquivos de config/infra) | ✅ Granular (infra) |
| T2: TranscriptionStore | 1 componente + testes | ✅ Granular |
| T3: DictationService | 1 protocolo + 1 impl | ✅ Granular |
| T4: AppModel + Clipboard | 1 orquestrador + 1 protocolo trivial (2-3 cohesive) | ✅ Granular |
| T5: Painel | 1 componente de UI | ✅ Granular |
| T6: StatusBar + builder | 1 componente + 1 função pura | ✅ Granular |
| T7: HotKeyController | 1 componente | ✅ Granular |
| T8: Wiring | 1 arquivo (AppDelegate) | ✅ Granular |
| T9: Edge cases | 1 preocupação (error paths) em 2 arquivos | ✅ Granular |

---

## Diagram-Definition Cross-Check

| Task | Depends On (task body) | Diagram Shows | Status |
| ---- | ---------------------- | ------------- | ------ |
| T1 | None | raiz | ✅ Match |
| T2 | T1 | T1→T2 | ✅ Match |
| T3 | T1 | T2→T3 (cadeia sequencial) | ✅ Match (T3 dep T1; diagrama sequencial OK) |
| T4 | T2, T3 | após T3 | ✅ Match |
| T5 | T4 | após T4 | ✅ Match |
| T6 | T2, T4 | após T4 | ✅ Match |
| T7 | T1 | após T3, paralelo | ✅ Match (dep mínima satisfeita) |
| T8 | T4, T5, T6, T7 | após todos | ✅ Match |
| T9 | T8 | T8→T9 | ✅ Match |

---

## Test Co-location Validation

| Task | Code Layer Created/Modified | Matrix Requires | Task Says | Status |
| ---- | --------------------------- | --------------- | --------- | ------ |
| T1 | infra/config | none | none | ✅ OK |
| T2 | domain (store) | unit | unit (≥5) | ✅ OK |
| T3 | system (speech) | none | none | ✅ OK |
| T4 | domain (model) | unit | unit (≥8) | ✅ OK |
| T5 | system (UI) | none | none | ✅ OK |
| T6 | domain (builder) + system (statusbar) | unit (highest) | unit (≥4) | ✅ OK |
| T7 | system (hotkey) | none | none | ✅ OK |
| T8 | system (wiring) | none (manual UAT) | none | ✅ OK |
| T9 | domain (error paths) | unit | unit (≥3) | ✅ OK |
