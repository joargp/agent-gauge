# Agent Gauge: details

The full reference: how each agent is read, custom status lines, building, releasing, and uninstalling. For a quick start, see the [README](../README.md).

Agent Gauge is a private, native macOS menu bar app for the subscription limits of your coding agents. It shows one menu bar item per agent, and you choose which ones appear:

- **Claude** — Claude Code's 5-hour and weekly windows on a Claude Pro or Max plan.
- **Codex** — Codex's 5-hour and weekly windows on a ChatGPT plan.

Each item draws two nested rings for the percentage remaining in each window. Its popover shows the remaining percentages, reset times, how old the reading is, and a settings menu (gear) with:

- **Show Claude** / **Show Codex** — add or remove that agent's menu bar item. A hidden agent does no background work. The last visible item can't be hidden.
- **Launch at Login** — registers Agent Gauge as a login item (System Settings → General → Login Items).

Some plans have no 5-hour window. Codex Pro Lite, for example, only reports a weekly limit. That ring then reads **No limit on this plan**.

## Download

Each [release](https://github.com/joargp/agent-gauge/releases) has a disk image, `AgentGauge.dmg`, built by GitHub Actions for both Apple silicon and Intel Macs. It also has `AgentGauge-<version>.zip`, which is what the built-in updater downloads.

1. Download [`AgentGauge.dmg`](https://github.com/joargp/agent-gauge/releases/latest/download/AgentGauge.dmg) and open it.
2. Drag **Agent Gauge** onto the Applications folder in the window that opens.
3. Open Agent Gauge from Applications. The welcome window lets you pick agents, connect Claude Code's status line, and turn on launch at login.

If you open it from somewhere else, such as the disk image or Downloads, Agent Gauge offers to move itself to Applications and open again from there. It can only update itself from Applications.

Builds from 0.1.2 on are signed with a Developer ID and notarized by Apple, so they open normally. Older builds are blocked on first launch; allow them in **System Settings → Privacy & Security → Open Anyway**, or run:

```bash
xattr -dr com.apple.quarantine "/Applications/Agent Gauge.app"
```

## Updates

From 0.1.5 on, Agent Gauge updates itself with [Sparkle](https://sparkle-project.org). Versions 0.1.4 and older can't, so download 0.1.5 or later by hand once.

Choose how in the gear menu under **Automatic Updates**:

- **Download, Install on Quit** (the default): checks once a day, downloads new versions in the background and installs them when Agent Gauge quits. A blue dot on the menu bar icon and a row in the popover say when one is ready; **Restart Now** installs it right away.
- **Notify Me**: checks once a day and shows the new version in the popover, with **Install** and **Later**.
- **Off**: never checks by itself. **Check for Updates…** still works. Turning this off doesn't cancel an update that has already been downloaded.

Agent Gauge reads its update feed from `https://joargp.github.io/agent-gauge/appcast.xml`. Every download is signed, and Sparkle refuses any that don't match the key built into the app. After an update, Agent Gauge also refreshes its copy of the Claude Code capture helper in `~/.claude/claude-gauge/`, without touching your settings.

## Claude

### Privacy and authentication

For Claude, Agent Gauge does **not** read your macOS Keychain, Claude OAuth token, prompts, transcripts, source code, or session history, and it makes no network requests of its own.

The one exception is the Fable limit (see below). For that, Agent Gauge asks your installed Claude Code to run `claude /usage`. Claude Code contacts Anthropic with its own login. Agent Gauge only sees the text it prints.

Claude Code officially supplies live subscription-rate-limit metadata to configured statusline commands. Agent Gauge installs a small local capture binary as that command. The helper receives the full statusline JSON on stdin, decodes only the fields below, and never persists the raw input:

- 5-hour and 7-day percentages used
- their reset timestamps
- the capture timestamp
- the Claude Code version

It writes that metadata atomically to:

```text
~/.claude/claude-gauge/last-usage.json
```

The menu bar app re-reads that file every ten seconds and on demand. This avoids the persistent macOS permission prompts caused when third-party apps poll Claude Code's Keychain item and token refresh recreates its access-control list.

### Data freshness

The cache updates while an interactive Claude Code session renders its status line. Usage cannot increase while Claude Code is idle, so the last captured value remains meaningful. Agent Gauge always displays its age:

- **Green** — captured within two minutes
- **Neutral** — captured within one hour
- **Orange** — older; likely no active Claude Code session

If a cached `resets_at` passes while Claude Code is idle, Agent Gauge stops showing the old percentage and marks that window **No recent data · Start Claude Code to refresh**.

The Refresh button re-reads the cache and installation state. The 5-hour and weekly windows only change when Claude Code renders its status line, so Refresh cannot force a new reading of those.

### Fable limit

Some plans have a separate weekly limit for Fable. Claude Code's status line does not include it, so Agent Gauge runs `claude -p "/usage" --output-format json --no-session-persistence` and reads the `Current week (Fable)` line. That command is local, makes no model call and costs nothing. It runs with `ANTHROPIC_API_KEY` and `ANTHROPIC_AUTH_TOKEN` removed, because with them set Claude Code prints API stats instead of subscription limits.

It is read when you open the Claude popover and when you press **Refresh**, never more than once a minute and never twice at once. The last value shows while a read runs, and the number updates in place when it finishes. Each run starts the whole Claude CLI, so background reads are rare: at most every 15 minutes, and only after the status line has captured new usage on this Mac. The Claude popover then shows a Fable row between the rings and the update time. If Claude Code is missing or your plan has no Fable limit, the row is simply not shown. A run that fails or takes longer than 20 seconds keeps the last reading, but after 30 minutes of failures the row is hidden rather than showing an old value. The CLI is found through `CLAUDE_GAUGE_CLAUDE_PATH`, `PATH`, or common install folders such as `~/.local/bin`.

### Existing custom status line

If you already use a custom status line, keep it and feed the same stdin JSON to Agent Gauge from your statusline command. First install only the helper:

```bash
CAPTURE="$(swift build --configuration release --show-bin-path)/claude-gauge-capture"
"$CAPTURE" install-helper
```

Then prefix your existing `statusLine.command` with:

```bash
tee >(~/.claude/claude-gauge/capture >/dev/null) | your-statusline-command
```

The exact wrapper depends on how your existing command reads stdin. The installer deliberately refuses to overwrite a custom status line.

When Agent Gauge writes the status line itself, the command is just the helper's path. If your home folder's path contains spaces or shell characters, the path is single-quoted. Agent Gauge reads and writes `~/.claude` only, so it doesn't follow `CLAUDE_CONFIG_DIR`. If you set that variable, connect the status line by hand as shown above.

If you later uninstall Agent Gauge, remove that tee segment from your custom statusLine command manually. The uninstaller refuses to delete the helper while a custom status line still references it.

### Diagnostics

```bash
~/.claude/claude-gauge/capture status
```

### Research basis

The Claude side relies only on Anthropic's documented statusline interface:

- https://code.claude.com/docs/en/statusline

Relevant documented fields:

```text
rate_limits.five_hour.used_percentage
rate_limits.five_hour.resets_at
rate_limits.seven_day.used_percentage
rate_limits.seven_day.resets_at
model.display_name
version
```

`rate_limits` appears for Claude.ai Pro/Max subscribers after the first API response, and Claude Code drops a window once its `resets_at` has passed.

## Codex

### Privacy and authentication

Agent Gauge uses the Codex login that already exists on this Mac. Once a minute, and when you press **Refresh**, it starts the installed `codex app-server` locally and asks it for `account/rateLimits/read` over stdio.

- It does **not** read, copy, or store Codex access or refresh tokens.
- It does **not** inspect prompts, sessions, transcripts, or source code.
- It does **not** log app-server stderr or credentials.
- Codex itself owns OAuth token refresh and account routing.

If the popover says Codex is not signed in, run:

```bash
codex login
```

### Finding the Codex CLI

Agent Gauge prefers the self-contained CLI bundled with the ChatGPT or Codex macOS app, then resolves `codex` from `PATH` and common user install locations, including `~/Library/pnpm/bin`. The child process PATH includes mise's Node shims, so pnpm's launcher can find Node even when the app starts with Finder's minimal PATH. For a custom install, set `CODEX_GAUGE_CODEX_PATH` to the executable path before launching the app.

### Research basis

Agent Gauge deliberately uses the local app-server instead of directly calling the private `https://chatgpt.com/backend-api/wham/usage` endpoint. This keeps credential storage, refresh, and workspace selection inside Codex.

- [Official Codex app-server protocol and rate-limit API](https://github.com/openai/codex/blob/656a2d0905c9e0b9bdade1badab07ef6d42ca17c/codex-rs/app-server/README.md)
- [Official backend usage client](https://github.com/openai/codex/blob/656a2d0905c9e0b9bdade1badab07ef6d42ca17c/codex-rs/backend-client/src/client.rs)
- [Official rate-limit payload models](https://github.com/openai/codex/blob/656a2d0905c9e0b9bdade1badab07ef6d42ca17c/codex-rs/codex-backend-openapi-models/src/models/rate_limit_status_payload.rs)
- [CodexBar's app-server integration](https://github.com/steipete/CodexBar/blob/b079e9bcd946304ca4ca916d0eff89b8453a273e/Sources/CodexBarCore/UsageFetcher.swift)

Windows are classified by their reported duration (`300` and `10,080` minutes), not by response order. `codex app-server` is currently labeled experimental by the CLI, so its wire protocol can evolve. The integration is covered with response fixtures and a gated live test.

## Requirements

- macOS 14 or newer
- Swift 6 / Xcode command-line tools
- For Claude: Claude Code 2.1.80 or newer, signed in with a Claude.ai Pro or Max subscription
- For Codex: a current Codex CLI installation signed in with a ChatGPT subscription

## Build, test, and run

```bash
swift test
./script/build_and_run.sh --verify
```

The run script builds a real menu-bar-only app bundle at:

```text
dist/Agent Gauge.app
```

Other supported modes:

```bash
./script/build_and_run.sh
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

To build the same universal app, zip and disk image that releases ship (the app icon needs Xcode 26 or later, and the disk image needs Node for `appdmg`):

```bash
AGENT_GAUGE_VERSION=0.1.0 ./script/package_release.sh
```

The build number (`CFBundleVersion`) comes from the version: 0.2.0 is 2000 and 1.4.12 is 1004012, so it always rises with the version. Versions must look like `1.2.3`.

Pushing a `v1.2.3` tag runs the Release workflow, which tests, packages, and attaches the zip to that GitHub release. To sign with a Developer ID and notarize, add these secrets to a GitHub environment named `release` that only `v*` tags may use: `MACOS_CERTIFICATE_P12` (base64), `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGNING_IDENTITY`, `NOTARY_KEY_P8` (base64), `NOTARY_KEY_ID` and `NOTARY_ISSUER_ID`. Without them the build is signed ad hoc.

For built-in updates, the same environment also needs the variable `SPARKLE_PUBLIC_KEY` and the secret `SPARKLE_PRIVATE_KEY`, from Sparkle's `generate_keys` (in `.build/artifacts/sparkle/Sparkle/bin/` after `swift build`). When everything is set, the workflow then:

1. downloads the zip from the release and checks its version, update key, signature and notarization;
2. signs that exact file with `sign_update`;
3. adds it to `site/appcast.xml` on `main` with `script/update_appcast.py`, using the release notes' bullet points as the in-app "What's new" list;
4. starts the Pages workflow to publish the feed.

A zip that is already on a release is never replaced, because installed apps check it against the signature in the feed. To publish a new build for the same version, delete the asset first. If anything is missing, the release is still created but isn't added to the feed. Builds without `AGENT_GAUGE_SPARKLE_PUBLIC_KEY`, including every local build, have no updater and show no update controls.

To verify the complete local Codex login and app-server path on this Mac:

```bash
CODEX_GAUGE_LIVE_TEST=1 swift test --filter LiveCodexIntegrationTests
```

This test reads only usage metadata and never prints tokens.

## Install from source

```bash
./script/install.sh
```

The installer:

1. Installs `Agent Gauge.app` to `~/Applications`.
2. Copies the Claude capture helper to `~/.claude/claude-gauge/capture` and adds this entry to `~/.claude/settings.json`:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "/Users/you/.claude/claude-gauge/capture"
     }
   }
   ```

3. Removes the earlier standalone Claude Gauge and Codex Gauge apps and their launch agents, if present.
4. Turns on launch at login and starts the app.

The installer fails closed for empty, unreadable, malformed, or foreign statusLine settings. It never rewrites them, and restores any previous Agent Gauge installation if setup fails.

After installation, restart any existing Claude Code sessions (or start a new one) and send one message. Sessions already running during installation may not load the new statusLine command.

If you use a menu bar manager such as Ice or Bartender, new items may start in its hidden section. Move them to the visible section there.

## Uninstall

To remove the app, its login item, and the exact user-level statusLine entry the installer added:

```bash
./script/uninstall.sh
```

The Claude helper and cache are intentionally preserved because project-local Claude settings can also reference them, and the uninstaller cannot safely discover every project. If any custom, foreign, malformed, or unreadable user statusLine remains, uninstall also fails closed. Symlink-managed user settings are updated through their resolved target without replacing the symlink. Remove or detach conflicting settings, then rerun.

After checking that no user or project status line references the helper, you can explicitly purge the preserved files:

```bash
rm -rf ~/.claude/claude-gauge
```

## Architecture

- `GaugeCore/` — shared usage models, display states, freshness, formatting, ring geometry, and the `UsageProvider` protocol
- `ClaudeProvider/` — statusline JSON decoding, cache format and reader, capture logic, and settings mutation
- `ClaudeGaugeCapture/` — fast stdin capture binary and statusLine install/uninstall commands
- `CodexProvider/` — Codex executable resolution, local app-server transport, and decoding
- `AgentGauge/App/` — menu bar scenes, provider visibility, launch at login, and the capture helper refresh
- `Resources/AppIcon.icon` — the app icon, an Icon Composer file compiled by `actool` during the build; `Resources/dmg/` holds the disk image background, drawn by `script/make_dmg_background.swift`
- `AgentGauge/Update/` — Sparkle updater with a custom driver (as in Ghostty) that shows update states in the popover
- `AgentGauge/Stores/` — per-provider refresh lifecycle and stale-data preservation
- `AgentGauge/Support/` — per-provider descriptor and palette
- `AgentGauge/Views/` — status label, popover, usage rings, data-age indicator, and settings menu

Claude cache updates are serialized with a local file lock and use atomic replacement. Concurrent sessions reconcile by reset timestamp and used percentage so an older session cannot regress a newer window.

## License

MIT. See [LICENSE](../LICENSE).

Agent Gauge is an independent project, not affiliated with Anthropic or OpenAI.
