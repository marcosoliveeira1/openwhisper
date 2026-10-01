# AGENTS.md — OpenWhisper

Repo: app macOS nativo (Swift 6, AppKit + SwiftUI). Sem dependências externas.

## Build (obrigatório ler antes de compilar)

O CLT 27.0 não traz `libSwiftUIMacros.dylib` (macros do SwiftUI quebradas no
SDK 27). O `Makefile` já contorna isso fixando `SDKROOT` no SDK 26.5.

- **Sempre compile/teste pelos targets do `make`** — eles aplicam o workaround:
  - `make build` — compila release
  - `make app` — compila + monta `build/OpenWhisper.app`
  - `make run` — monta + abre o app
  - `make test` — roda a suíte (Swift Testing)
- **Nunca chame `swift build` / `swift test` direto sem `SDKROOT`** — falha com
  `external macro implementation type 'SwiftUIMacros.StateMacro' could not be found`.
  Se precisar chamar o `swift` direto, exporte antes:
  ```bash
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
  swift test
  ```

## Instalar por cima (kill + rm + novo)

`make run` só abre o `.app` novo; se uma versão antiga estiver rodando, o
sistema pode manter a antiga. Fluxo correto para trocar o app em uso:

1. **Pergunte ao usuário antes** se pode encerrar e substituir o app instalado.
2. Com confirmação: `pkill -x OpenWhisper`, apague o `.app` antigo,
   `make app`, abra o novo.
3. Atenção: cada `make app` gera um binário novo e o macOS invalida o grant
   de Acessibilidade — o usuário precisa reativar em
   Ajustes → Privacidade → Acessibilidade (a tela de Configurações explica isso).

## Testes

- `GatewayTests` é `@Suite(.serialized)`: mexe em `UserDefaults.standard`
  (prefixos `gateway*`, chave `aiProvider`) e restaura tudo no `defer` via
  `withGateway`. Não quebre esse isolamento.
- Defaults de modelo ficam em `AIProvider.defaultModel` com fallback em
  `GatewayStore.config(for:)`; modelos aposentados vão em
  `AIProvider.retiredModels` para migrar prefs antigas — atualize os dois
  juntos e ajuste `GatewayTests.presets`.
