# Codex Gauge

Codex Gauge is a private, native macOS menu bar app for the two ChatGPT Codex subscription limits that matter most:

- **5-hour usage** — a ring showing the percentage remaining in the rolling five-hour window.
- **Weekly usage** — a second ring showing the percentage remaining in the weekly window.

The menu bar also shows both remaining percentages at a glance. Usage refreshes at launch, once per minute, and whenever you press **Refresh**.

## Privacy and authentication

Codex Gauge uses the Codex login that already exists on this Mac. It starts the installed `codex app-server` locally and asks it for `account/rateLimits/read` over stdio.

- It does **not** read, copy, or store Codex access or refresh tokens.
- It does **not** inspect prompts, sessions, transcripts, or source code.
- It does **not** log app-server stderr or credentials.
- Codex itself owns OAuth token refresh and account routing.

If the app says Codex is not signed in, run:

```bash
codex login
```

## Requirements

- macOS 14 or newer
- Swift 6 / Xcode command-line tools
- A current Codex CLI installation signed in with a ChatGPT subscription

Codex Gauge prefers the self-contained CLI bundled with the ChatGPT or Codex macOS app, then resolves `codex` from `PATH` and common user install locations, including `~/Library/pnpm/bin`. This avoids GUI-launch PATH issues where a package-manager shim cannot find Node. For a custom install, set `CODEX_GAUGE_CODEX_PATH` to the executable path before launching the app.

## Build, test, and run

```bash
swift test
./script/build_and_run.sh --verify
```

The run script builds a real menu-bar-only app bundle at:

```text
dist/Codex Gauge.app
```

Other supported modes:

```bash
./script/build_and_run.sh
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

The project-local Codex Run action in `.codex/environments/environment.toml` uses the same script.

## Install and launch at login

Install an optimized, ad-hoc-signed local copy to `~/Applications` and register
it to launch whenever you log in:

```bash
./script/install.sh
```

The installer writes `~/Library/LaunchAgents/com.joar.codexgauge.plist`, starts
the app immediately, and starts a fresh menu-bar process on future Aqua login
sessions. It uses no privileged installer or password.

To remove the local installation and login item:

```bash
./script/uninstall.sh
```

### Optional live integration test

The normal suite uses deterministic fixtures. To verify the complete local Codex login and app-server path on this Mac:

```bash
CODEX_GAUGE_LIVE_TEST=1 swift test --filter LiveCodexIntegrationTests
```

This test reads only usage metadata and never prints tokens.

## Architecture

- `App/` — menu bar scene entry point
- `Views/` — status label, popover, and usage rings
- `Stores/` — one-minute refresh lifecycle and stale-data preservation
- `Services/` — Codex executable resolution, local app-server transport, and decoding
- `Models/` — normalized quota windows and remaining-use calculation
- `Support/` — compact reset and status formatting

The app classifies windows by their reported duration (`300` minutes and `10,080` minutes), rather than assuming the backend always returns them in a fixed order.

## Research basis

Codex Gauge deliberately uses the local app-server instead of directly calling the private `https://chatgpt.com/backend-api/wham/usage` endpoint. This keeps credential storage, refresh, and workspace selection inside Codex.

Relevant upstream references:

- [Official Codex app-server protocol and rate-limit API](https://github.com/openai/codex/blob/656a2d0905c9e0b9bdade1badab07ef6d42ca17c/codex-rs/app-server/README.md)
- [Official backend usage client](https://github.com/openai/codex/blob/656a2d0905c9e0b9bdade1badab07ef6d42ca17c/codex-rs/backend-client/src/client.rs)
- [Official rate-limit payload models](https://github.com/openai/codex/blob/656a2d0905c9e0b9bdade1badab07ef6d42ca17c/codex-rs/codex-backend-openapi-models/src/models/rate_limit_status_payload.rs)
- [CodexBar's app-server integration](https://github.com/steipete/CodexBar/blob/b079e9bcd946304ca4ca916d0eff89b8453a273e/Sources/CodexBarCore/UsageFetcher.swift)

`codex app-server` is currently labeled experimental by the CLI, so its wire protocol can evolve. The integration is isolated behind `CodexUsageFetching` and covered with response fixtures and a gated live test.
