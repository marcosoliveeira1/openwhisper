# OpenWhisper MVP Validation

**Date**: 2026-09-04
**Spec**: `.specs/features/openwhisper-mvp/spec.md`
**Diff range**: `f577d6c..f29a3ed` (9 commits: scaffold, store, speech, appmodel, hotkey, statusbar, panel, wiring, edge cases)
**Verifier**: independent sub-agent (author ≠ verifier)

---

## Task Completion

| Task | Status | Notes |
| ---- | ------ | ----- |
| T1: Scaffold + app tray mínimo | ✅ Done | `swift build`/`make app` OK; `LSUIElement` em `Info.plist:21` |
| T2: Transcription + TranscriptionStore | ✅ Done | 6 unit tests (cap, ordering, round-trip, clear, missing/corrupt file) |
| T3: DictationService + AppleSpeechService | ✅ Done | System layer — build gate; protocolo injetável confirmado |
| T4: AppModel + Clipboard | ✅ Done | 13 unit tests com mocks (alvo ≥8 superado) |
| T5: Painel flutuante NSPanel + SwiftUI | ✅ Done | System layer — build gate; view reflete estados do AppModel |
| T6: StatusBarController + HistoryMenuBuilder | ✅ Done | 6 unit tests do builder puro (alvo ≥4 superado) |
| T7: HotKeyController ⌘⇧G | ✅ Done | System layer — build gate; wiring em `AppDelegate.swift:23-25` |
| T8: Integração completa (wiring) | ✅ Done (código) | UAT manual do checklist **pendente do usuário** |
| T9: Edge cases e polimento | ✅ Done | 3+ novos tests: empty-finish, interrupted-partial, transcribing-ignore |

Nenhuma task bloqueada ou parcial. Total: 25 testes (13 AppModel + 6 Store + 6 Builder), todos passando.

---

## Spec-Anchored Acceptance Criteria

### P1: Ditado via atalho global (OW-01..03)

| Criterion (WHEN X THEN Y) | Spec-defined outcome | `file:line` + assertion | Result |
| ------------------------- | -------------------- | ----------------------- | ------ |
| **OW-01** WHEN ⌘⇧G THEN painel flutuante sem roubar foco + grava imediatamente | Hotkey global abre painel + `start()` do mic imediato | `Tests/OpenWhisperTests/AppModelTests.swift:76-83` — `toggle()` de `.idle` → estado `.recording` (= `dictation.start()` chamado via contrato `DictationService`); hotkey Carbon/NSPanel sem foco: `Sources/OpenWhisper/AppDelegate.swift:23-25`, `Sources/OpenWhisper/HotKeyController.swift` | ⚠️→✅ System layer (hotkey/panel/foco) — **UAT manual**; parte de máquina de estados coberta por unit conforme matriz de cobertura |
| **OW-02** WHEN painel abre THEN indicador visível (timer + mic) e sem Dock | Timer + ícone no painel; `LSUIElement` | `Sources/OpenWhisper/Panel/DictationView.swift:25-35` (ponto vermelho + "Gravando" + `TimelineView` timer); `Info.plist:21` (`LSUIElement`) | ⚠️→✅ System layer (UI visual) — **UAT manual**; wiring/manifest verificados no código |
| **OW-03** WHEN 1º uso THEN pede permissões; negadas THEN msg + botão Ajustes | `.failed(.permissionDenied)` com zero side effects + botão "Abrir Ajustes" | `Tests/OpenWhisperTests/AppModelTests.swift:157-170` — `#expect(model.state == .failed(.permissionDenied))`, `clipboard.copied.isEmpty`, `history.isEmpty`; botão: `Sources/OpenWhisper/Panel/DictationView.swift:48-53` (abre `x-apple.systempreferences:` Privacy_Microphone) | ✅ PASS (unit no estado; botão = system layer, string/URL verificadas no código) |

### P1: Finalizar → texto na clipboard (OW-04..06)

| Criterion | Spec-defined outcome | `file:line` + assertion | Result |
| --------- | -------------------- | ----------------------- | ------ |
| **OW-04** WHEN Finalizar THEN para gravação, transcrição pt-BR, copia, fecha painel, adiciona ao histórico | Clipboard == transcript; histórico contém transcript; estado volta a `.idle` (painel fecha) | `Tests/OpenWhisperTests/AppModelTests.swift:85-101` — `#expect(clipboard.copied == ["olá mundo"])`, `#expect(history.map(\.text) == ["olá mundo"])`, `#expect(model.state == .idle)`; pt-BR = system layer (SFSpeechRecognizer locale) | ✅ PASS |
| **OW-05** WHEN ⌘⇧G com painel aberto THEN mesmo fluxo de Finalizar | 2º toggle executa finish completo (copia + persiste) | `Tests/OpenWhisperTests/AppModelTests.swift:92-99` — 2º `toggle()` → mesmas assertions de clipboard/histórico; regra: `Sources/OpenWhisper/AppModel.swift:37-38` (`case .recording: finishDictation()`) | ✅ PASS |
| **OW-06** WHEN Cancelar/Esc THEN para, descarta tudo, fecha, NÃO altera histórico nem clipboard | Clipboard vazia; histórico vazio; estado `.idle` | `Tests/OpenWhisperTests/AppModelTests.swift:103-119` — `#expect(clipboard.copied.isEmpty)`, `#expect(history.isEmpty)`, `#expect(model.state == .idle)`; também cancel durante transcrição: `:205-226`; Esc = `.cancelAction` em `Sources/OpenWhisper/Panel/DictationView.swift:71-74` | ✅ PASS |

### P1: Histórico no tray (OW-07..10)

| Criterion | Spec-defined outcome | `file:line` + assertion | Result |
| --------- | -------------------- | ----------------------- | ------ |
| **OW-07** WHEN tray THEN recentes primeiro, label ~60 chars, tooltip completo, click copia integral | Ordem store preservada; label truncada 60+"…"; payload = texto completo | `Tests/OpenWhisperTests/HistoryMenuBuilderTests.swift:15-20` — `#expect(items[0].title == String(repeating:"a",count:60) + "…")`, `count == 61`; ordem: `:28-34`; payload integral: `:52-61` (`#expect(payload == full)`, `count == 100`); tooltip + click-to-copy: `Sources/OpenWhisper/StatusBar/StatusBarController.swift:40` (`toolTip = text`) e `:54-57` (`copyToClipboard(text)`) | ✅ PASS (builder unit; tooltip/click = system layer wiring verificado no código) |
| **OW-08** WHEN 50 entradas THEN descarta a mais antiga ao inserir nova | count == 50; primeira == 51ª; última == 2ª | `Tests/OpenWhisperTests/TranscriptionStoreTests.swift:21-30` — `#expect(all.count == 50)`, `#expect(all.first?.text == "texto 51")`, `#expect(all.last?.text == "texto 2")` | ✅ PASS (assertion exata do spec-defined outcome) |
| **OW-09** WHEN reinicia THEN carrega histórico de `~/Library/Application Support/OpenWhisper/history.json` | Round-trip JSON entre instâncias (modelo de restart); path exato no wiring | `Tests/OpenWhisperTests/TranscriptionStoreTests.swift:32-42` — nova instância mesma URL: `#expect(all.count == 1)`, `first?.text == "oi mundo"`; path default: `Sources/OpenWhisper/AppDelegate.swift:11-13` (`applicationSupportDirectory/OpenWhisper/history.json`) | ✅ PASS (restart modelado por nova instância conforme design "URL injetável"; path exato verificado no código — wiring = build gate pela matriz) |
| **OW-10** WHEN menu aberto THEN itens fixos Limpar histórico e Sair | Kinds `.clear` e `.quit` sempre presentes | `Tests/OpenWhisperTests/HistoryMenuBuilderTests.swift:36-43` — `kinds(items).contains(.clear)`, `.contains(.quit)`; `:45-50` — `#expect(items.last?.title == "Sair")` | ✅ PASS |

**P2 (OW-11 preview ao vivo, OW-12 atalho configurável)**: fora de escopo do MVP — não avaliados (spec os marca P2; traceability permanece Pending).

**Status**: ✅ 10/10 ACs P1 com outcome conforme spec (7 com assertion unit direta; OW-01/02 parcialmente system-layer conforme matriz de cobertura em tasks.md — "none — build gate + manual UAT"). **0 spec-precision gaps graves**. Nota menor: spec diz truncamento "~60 chars" (aproximado) — implementação exata em 60+"…" satisfaz e o teste é mais preciso que a spec (sem gap).

---

## Discrimination Sensor

| Mutation | File:line | Description | Killed? |
| -------- | --------- | ----------- | ------- |
| 1 | `Sources/OpenWhisper/TranscriptionStore.swift:26` | Cap do histórico: `removeLast` → `removeFirst` (descarta as mais recentes em vez das antigas) | ✅ Killed — `addCapsAtFiftyDroppingOldest` falhou em 2 assertions (`first == "texto 50"`, `last == "texto 1"`) |
| 2 | `Sources/OpenWhisper/AppModel.swift:40` | `case .transcribing: break` → `startDictation()` (toggle em transcrição reinicia em vez de ignorar) | ✅ Killed — `toggleDuringTranscribingIsIgnored` falhou (estado virou `.recording`, esperado `.transcribing`) |
| 3 | `Sources/OpenWhisper/StatusBar/HistoryMenuBuilder.swift:39` | Removido sufixo `"…"` do truncate | ✅ Killed — `truncatesLongTextAtLimitWithEllipsis` falhou em 2 assertions (title sem "…", count 60 ≠ 61) |

**Sensor depth**: lightweight (3 mutações comportamentais no domínio de maior risco: cap de dados, máquina de estados, regra de truncamento spec-anchored)
**Result**: 3/3 killed — PASS ✅ (todas as mutações revertidas via `git checkout --`; tree limpo confirmado com `git status`)

---

## Interactive UAT Results

**⏳ PENDENTE DO USUÁRIO/ORCHESTRATOR** — não executado pelo Verifier (conforme instrução). Itens que exigem UAT manual (system layer, por matriz de cobertura em tasks.md):

1. ⌘⇧G em app em foco → painel flutua sem roubar foco, grava < 1s (OW-01)
2. Indicador de gravação + timer visíveis; nada no Dock (OW-02)
3. Permissão negada → msg inline + "Abrir Ajustes" funciona (OW-03, UI)
4. Ditar "olá mundo" → Finalizar → ⌘V cola "olá mundo" (OW-04, pt-BR real)
5. Tray: tooltip completo, click-to-copy, restart preserva histórico (OW-07/09 end-to-end)

---

## Code Quality

| Check | Pass? |
| ----- | ----- |
| No features beyond what was asked | ✅ (retry pós-falha e reset de live transcript são completude da máquina de estados, não scope creep) |
| No abstractions for single-use code | ✅ (`DictationService`/`Clipboard` protocolos existem para testabilidade, justificados no design) |
| No unnecessary "flexibility" added | ✅ (URL de arquivo injetável — previsto no design; sem configs extras) |
| Only touched files required for task | ✅ (diff surface = 9 commits, todos mapeados a T1..T9) |
| Didn't "improve" unrelated code | ✅ (greenfield; nada fora do escopo tocado) |
| Matches existing patterns/style | ✅ (SPM, atores/`@MainActor`, Swift Testing consistentes entre si) |
| Would senior engineer approve? | ✅ (separação limpa domínio/system, error mapping centralizado) |
| Tests map to ACs and are non-shallow (spot-check P1-Finalizar) | ✅ (`toggleDuringRecordingFinishesCopiesAndStores` verifica clipboard E histórico E estado final, não só "não crasha") |
| Spec-anchored outcome check | ✅ (ver seção ACs — valores assertidos = outcomes da spec) |
| Per-layer Coverage Expectation met | ✅ (domínio 1:1 com OW-04..10 e edge cases; system layer "none — build gate + UAT" conforme matriz) |
| Every test maps to a spec requirement — no unclaimed tests | ✅ (25/25 mapeados: ver tabela abaixo) |
| Documented guidelines followed | ✅ ("none — strong defaults applied" conforme tasks.md; Swift 6 concurrency/`Sendable` respeitado) |

**Mapa de testes sem claim direto em AC** (todos justificados):
- `missingFileStartsEmpty` / `corruptFileStartsEmpty` → T2 done-when ("empty-file reload") + design Error Handling ("histórico corrompido → inicia vazio")
- `finishOutsideRecordingIsNoOp` → robustez de OW-04 (guard contra finish fora de recording)
- `restartAfterCancelResetsLiveTranscript` → OW-06 ("descarta tudo" inclui partials) + start limpo
- `toggleFromFailureRestartsRecording` → recuperação pós OW-03 (saída do estado `.failed` via atalho)
- `clearHistoryEmptiesStore` / `copyToClipboardUsesClipboardService` → OW-10 / OW-07 (comportamento dos itens do menu no AppModel)

---

## Edge Cases

- [x] Transcrição final vazia (silêncio) → "Nenhuma fala detectada" no painel, sem copiar, sem histórico: `AppModelTests.swift:121-136` (`.failed(.noSpeech)` + clipboard/histórico vazios); string exata em `DictationView.swift:93` — **handled**
- [x] Falha do serviço de reconhecimento → erro inline, descarta sessão, nada copiado: `AppModelTests.swift:157-170` (permissionDenied) e `:228-240` (recognitionUnavailable, nada copiado); mensagens inline em `DictationView.swift:94-96`; parcial em falha de task → `AppleSpeechService` (system layer, T9) — **handled**
- [x] Áudio desconectado / sleep no meio → finaliza graciosamente entregando o que há: `AppModelTests.swift:260-279` (`interruptedDictationDeliversPartialOnFinish` — parcial copiado + persistido); detecção de interrupção no `AppleSpeechService` (system layer) — **handled**
- [x] ⌘⇧G durante transcrição → ignorar: `AppModelTests.swift:138-155` (estado permanece `.transcribing`, `startCount == 1`) — **handled** (mutação 2 do sensor confirmou que o teste discrimina)
- [x] Sem histórico → item desabilitado "Sem transcrições": `HistoryMenuBuilderTests.swift:36-43` (title + kind `.empty`); `isEnabled = false` em `StatusBarController.swift:42` — **handled**

---

## Gate Check

- **Gate command**: `swift test && swift build -c release && make app`
- **Result**: 25 passed, 0 failed, 0 skipped
- **Test count before feature**: 0 (greenfield — scaffold com suíte vazia)
- **Test count after feature**: 25
- **Delta**: +25 novos testes
- **Skipped tests**: none
- **Failures**: none (`swift build -c release` limpo; `make app` produziu `build/OpenWhisper.app` assinado ad-hoc com bundle id `br.marcos.openwhisper`)
- **Test integrity**: nenhuma suíte deletada/enfraquecida (greenfield, contagem só cresceu)

---

## Requirement Traceability Update

| Requirement | Previous Status | New Status |
| ----------- | --------------- | ---------- |
| OW-01 | Design/Pending | ✅ Verified (unit de máquina de estados; hotkey/panel/foco pendem UAT manual) |
| OW-02 | Design/Pending | ✅ Verified (wiring/manifest; visual pendem UAT manual) |
| OW-03 | Design/Pending | ✅ Verified (estado + zero side effects por unit; botão Ajustes verificado no código) |
| OW-04 | Design/Pending | ✅ Verified |
| OW-05 | Design/Pending | ✅ Verified |
| OW-06 | Design/Pending | ✅ Verified |
| OW-07 | Design/Pending | ✅ Verified |
| OW-08 | Design/Pending | ✅ Verified |
| OW-09 | Design/Pending | ✅ Verified |
| OW-10 | Design/Pending | ✅ Verified |
| OW-11 (P2) | Pending | ⏸️ Out of scope MVP — inalterado |
| OW-12 (P2) | Pending | ⏸️ Out of scope MVP — inalterado |

---

## Summary

**Overall**: ✅ Ready (com UAT interativa pendente do usuário)

**Spec-anchored check**: 10/10 ACs P1 matched spec outcome | 0 spec-precision gaps relevantes
**Sensor**: 3/3 mutations killed
**Gate**: 25 passed, 0 failed, 0 skipped (delta +25, greenfield)

**What works**:
- Máquina de estados completa (toggle/finish/cancel/failure) com todos os caminhos testados via mocks
- Store com cap 50 (descarta mais antiga), persistência JSON round-trip, clear, robustez a arquivo ausente/corrompido
- Builder de menu puro: truncamento 60+"…", ordenação, payload integral, estado vazio, itens fixos
- Todos os 5 edge cases da spec com caminho de código + cobertura unit onde mockável
- Wiring completo (AppDelegate): hotkey ⌘⇧G, painel, tray, store em Application Support

**Issues found**: none blocking. Única pendência: UAT interativa (5 itens listados) — comportamento de sistema (mic/voz/hotkey/foco) não é automatizável headless, conforme matriz de cobertura.

**Next steps**: usuário/orchestrator executa o checklist UAT manual (seção Interactive UAT); após UAT OK, feature pode ser marcada como concluída. OW-11/OW-12 permanecem para specs P2 próprias.
