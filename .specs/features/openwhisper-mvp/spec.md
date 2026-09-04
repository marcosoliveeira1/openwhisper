# OpenWhisper MVP Specification

## Problem Statement

Ditar texto no macOS hoje exige abrir apps pesados, clicar em botões e colar manualmente. O usuário quer apertar um atalho, falar, e ter o texto na área de transferência em segundos — com histórico consultável, sem abrir mão de leveza (sem Electron, sem WebView).

## Goals

- [ ] Ditado em ≤ 1s após atalho (painel flutuante grava imediatamente)
- [ ] Texto na clipboard ao finalizar, sem permissão de Acessibilidade
- [ ] App tray-only (sem ícone no Dock), binário nativo Swift, sem dependências de terceiros

## Out of Scope

| Feature | Reason |
| ------- | ------ |
| Correção por IA (API compatível OpenAI) | Próxima feature explícita do usuário — spec própria depois |
| Auto-paste no app em foco | Usuário escolheu auto-copy; exigiria permissão de Acessibilidade |
| Multi-idioma | Usuário escolheu pt-BR fixo |
| Configuração de atalho na UI | P2 — MVP fixo em ⌘⇧G |
| Ícone no Dock / janela principal | É app de tray |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --------------------- | -------------- | --------- | ---------- |
| Tech stack | Swift nativo (AppKit + SwiftUI), SFSpeechRecognizer, zero deps externas | "Mais leve possível" → binário nativo, sem runtime/WebView | y (implícito no pedido) |
| Nome do app | OpenWhisper | Nome do diretório | y |
| Atalho pressionado com painel já aberto | Finaliza (= botão Finalizar) | Comportamento toggle natural de apps de ditado | y — confirmado pelo usuário |
| Gravação muito longa | Sem cap rígido no MVP; UI mostra duração | Speech API on-device lida com sessões longas; cap automático pode vir depois | y — confirmado pelo usuário |
| Persistência do histórico | JSON em `~/Library/Application Support/OpenWhisper/history.json` | Leve, sem SQLite para 50 itens | n — assumption |
| Botão Copiar extra no painel | Não — auto-copy + histórico click-to-copy cobrem | Fluxo escolhido fecha o painel ao finalizar | n — assumption |

**Open questions:** none — all resolved or logged above.

---

## User Stories

### P1: Ditado via atalho global ⭐ MVP

**User Story**: As a user, I want to press ⌘⇧G anywhere and have a floating panel recording my voice immediately, so that dictation is faster than typing.

**Why P1**: É o gatilho central do app — sem isso nada mais importa.

**Acceptance Criteria**:

1. WHEN o usuário pressiona ⌘⇧G em qualquer app THEN system SHALL abrir um painel flutuante acima de todas as janelas, sem roubar o foco do app em uso, e iniciar a gravação do microfone imediatamente.
2. WHEN o painel abre THEN system SHALL exibir indicador visível de gravação (ex.: timer + ícone de mic) e o app SHALL NÃO aparecer no Dock.
3. WHEN o app roda pela primeira vez THEN system SHALL solicitar permissões de Microfone e Reconhecimento de Fala; se negadas, SHALL exibir no painel mensagem de erro com botão que abre os Ajustes do Sistema.

**Independent Test**: Rodar app (aparece ícone no menu bar, nada no Dock) → focar Safari → ⌘⇧G → painel flutua sobre o Safari e grava.

---

### P1: Finalizar → texto na clipboard ⭐ MVP

**User Story**: As a user, I want to click Finalizar (or re-press the hotkey) and have the transcribed text in my clipboard, so that I can paste it anywhere.

**Why P1**: É a entrega de valor final do fluxo.

**Acceptance Criteria**:

1. WHEN o usuário clica em Finalizar THEN system SHALL parar a gravação, obter a transcrição final (pt-BR), copiá-la para a clipboard, fechar o painel e adicionar a transcrição ao histórico.
2. WHEN o usuário pressiona ⌘⇧G com o painel já aberto THEN system SHALL executar o mesmo fluxo de Finalizar (assumption).
3. WHEN o usuário clica em Cancelar (ou pressiona Esc) THEN system SHALL parar a gravação, descartar tudo, fechar o painel e NÃO alterar histórico nem clipboard.

**Independent Test**: Ditar "olá mundo" → Finalizar → ⌘V num editor cola "olá mundo".

---

### P1: Histórico no tray ⭐ MVP

**User Story**: As a user, I want my last ~50 transcriptions accessible from the tray menu with click-to-copy, so that I can recover earlier dictations.

**Why P1**: Pedido explícito (app tray com histórico); sem persistência o app perde valor entre restarts.

**Acceptance Criteria**:

1. WHEN o usuário clica no ícone de tray THEN system SHALL exibir menu com as transcrições mais recentes primeiro (texto truncado a ~60 chars como label; tooltip com texto completo), e clicar numa entrada SHALL copiá-la integralmente para a clipboard.
2. WHEN o histórico atinge 50 entradas THEN system SHALL descartar a mais antiga ao inserir nova.
3. WHEN o app reinicia THEN system SHALL carregar o histórico persistido em JSON (`~/Library/Application Support/OpenWhisper/history.json`).
4. WHEN o menu de tray é aberto THEN system SHALL exibir também os itens fixos: Limpar histórico e Sair.

**Independent Test**: Ditar 3 frases → tray mostra 3 entradas → clique na 2ª → ⌘V cola a 2ª → reiniciar app → entradas seguem lá.

---

### P2: Preview de transcrição ao vivo

**User Story**: As a user, I want to see the partial transcription while I speak, so that I know recognition is working.

**Why P2**: Inerente à SFSpeechRecognizer (parciais vêm grátis), mas não bloqueia o MVP.

**Acceptance Criteria**:

1. WHEN o reconhecedor emite resultados parciais THEN system SHALL exibi-los em tempo real no painel.

**Independent Test**: Falar uma frase longa e ver o texto crescendo antes de finalizar.

---

### P2: Atalho configurável

**User Story**: As a user, I want to change the global hotkey, so that it doesn't conflict with other apps.

**Why P2**: Usuário pediu "configurável", mas fixou ⌘⇧G para o MVP.

**Acceptance Criteria**:

1. WHEN o usuário altera o atalho nas preferências THEN system SHALL re-registrar o atalho global e persisti-lo entre restarts.

**Independent Test**: Trocar para ⌥Space → fechar → reabrir → ⌥Space funciona, ⌘⇧G não.

---

## Edge Cases

- WHEN a transcrição final vem vazia (silêncio) THEN system SHALL mostrar "Nenhuma fala detectada" no painel, fechar sem copiar e NÃO adicionar ao histórico.
- WHEN o serviço de reconhecimento falha (Speech server indisponível / erro de engine) THEN system SHALL exibir erro inline no painel, descartar a sessão e não copiar nada.
- WHEN o dispositivo de áudio é desconectado ou o sistema dorme no meio da gravação THEN system SHALL finalizar a sessão graciosamente e entregar o que foi transcrito até ali.
- WHEN ⌘⇧G é pressionado durante a fase de transcrição (após Finalizar) THEN system SHALL ignorar (painel já em encerramento).
- WHEN não há histórico THEN system SHALL exibir item desabilitado "Sem transcrições" no menu.

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| -------------- | ----- | ----- | ------ |
| OW-01 | P1: Ditado via atalho | Design | Pending |
| OW-02 | P1: Ditado via atalho | Design | Pending |
| OW-03 | P1: Ditado via atalho | Design | Pending |
| OW-04 | P1: Finalizar | Design | Pending |
| OW-05 | P1: Finalizar | Design | Pending |
| OW-06 | P1: Finalizar | Design | Pending |
| OW-07 | P1: Histórico no tray | Design | Pending |
| OW-08 | P1: Histórico no tray | Design | Pending |
| OW-09 | P1: Histórico no tray | Design | Pending |
| OW-10 | P1: Histórico no tray | Design | Pending |
| OW-11 | P2: Preview ao vivo | - | Pending |
| OW-12 | P2: Atalho configurável | - | Pending |

**Coverage:** 12 total, 0 mapped to tasks, 12 unmapped ⚠️ (mapped in Tasks phase)

---

## Success Criteria

- [ ] ⌘⇧G → gravação em < 1s, painel acima de qualquer app, foco do app em uso preservado
- [ ] Finalizar → texto correto na clipboard (pt-BR), painel fecha
- [ ] Cancelar → zero side effects (clipboard e histórico intactos)
- [ ] Histórico: 50 itens max, sobrevive a restart, click-to-copy
- [ ] App sem ícone no Dock, sem dependências de terceiros, footprint de memória ≤ ~100MB
