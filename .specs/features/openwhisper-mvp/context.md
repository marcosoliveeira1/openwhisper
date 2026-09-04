# OpenWhisper MVP Context

**Gathered:** 2026-09-04
**Spec:** `.specs/features/openwhisper-mvp/spec.md`
**Status:** Ready for design

---

## Feature Boundary

App macOS de tray (sem Dock) para ditado: atalho global ⌘⇧G abre painel flutuante gravando a voz, transcrição via Speech API (pt-BR), Finalizar copia o texto para a clipboard, Cancelar descarta. Histórico das últimas ~50 transcrições no menu do tray, click-to-copy, persistido em JSON. Próxima feature (fora deste escopo): botão de correção por IA via API compatível OpenAI.

---

## Implementation Decisions

### Atalho global

- MVP: fixo em **⌘⇧G** (usuário: "configurável mas agora cmd+shift+g")
- Configurabilidade → P2, spec própria do requisito OW-12

### Entrega do texto

- **Auto-copy ao Finalizar** → painel fecha → usuário cola com ⌘V
- Sem auto-paste: evita permissão de Acessibilidade
- Cancelar (e Esc) = descarte total, sem tocar clipboard/histórico

### Idioma

- **pt-BR fixo** no SFSpeechRecognizer; multi-idioma rejeitado pelo usuário

### Histórico

- Últimas ~50, mais recente primeiro, click-to-copy
- Label truncado (~60 chars) no menu, texto completo no tooltip
- Persistência JSON em `~/Library/Application Support/OpenWhisper/history.json`
- Itens fixos do menu: Limpar histórico, Sair

### Agente decide (discretion concedida)

- Layout visual do painel (leve, minimalista: indicador de gravação + timer + botões)
- Estrutura interna do JSON do histórico
- Mecanismo de atalho global (Carbon RegisterEventHotKey vs NSEvent global monitor)

### Declined / Undiscussed → Assumptions

- Atalho com painel aberto = Finalizar (toggle) → spec assumption
- Sem cap de duração de gravação no MVP → spec assumption
- Sem botão Copiar redundante no painel → spec assumption

---

## Specific References

- Comportamento-alvo implícito: apps como Superwhisper/WhisperFlow (atalho → fala → texto no clipboard)
- Usuário enfatizou duas vezes: **"da forma mais leve possivel"** → nativo Swift, zero deps, tray-only

---

## Deferred Ideas

- **Correção por IA (API compatível OpenAI, configurável)** — próxima feature explícita do usuário; merece spec própria (config de endpoint/key, prompts, diff/undo)
- Multi-idioma selecionável
- Auto-paste com permissão de Acessibilidade
