# Claude Gauge

Claude Gauge is a private, native macOS menu bar app for the two Claude Code subscription limits that matter most on a Claude Max plan:

- **5-hour usage** — a ring showing the percentage remaining in the active five-hour window.
- **Weekly usage** — a second ring showing the percentage remaining in the seven-day window.

The menu bar shows both remaining percentages at a glance. The popover also shows how old the last capture is.

## Privacy and authentication

Claude Gauge does **not** read your macOS Keychain, Claude OAuth token, prompts, transcripts, source code, or session history. It makes no network requests.

Claude Code officially supplies live subscription-rate-limit metadata to configured statusline commands. Claude Gauge installs a small local capture binary as that command. The helper receives the full statusline JSON on stdin, decodes only the fields below, and never persists the raw input:

- 5-hour and 7-day percentages used
- their reset timestamps
- the capture timestamp
- the Claude Code version

It writes that metadata atomically to:

```text
~/.claude/claude-gauge/last-usage.json
```

The menu bar app re-reads that file every ten seconds and on demand. This avoids the persistent macOS permission prompts caused when third-party apps poll Claude Code's Keychain item and token refresh recreates its access-control list.

## Data freshness

The cache updates while an interactive Claude Code session renders its status line. Usage cannot increase while Claude Code is idle, so the last captured value remains meaningful. Claude Gauge always displays its age:

- **Green** — captured within two minutes
- **Neutral** — captured within one hour
- **Orange** — older; likely no active Claude Code session

If a cached `resets_at` passes while Claude Code is idle, Claude Gauge stops showing the old percentage and marks that window **Rolled over · Awaiting next capture**.

The Refresh button re-reads the cache and installation state. Claude Code currently exposes no non-interactive `usage` command, so the app cannot force the CLI to produce a new server-side reading.

## Requirements

- macOS 14 or newer
- Swift 6 / Xcode command-line tools
- Claude Code 2.1.80 or newer, signed in with a Claude.ai Pro or Max subscription

Your local Claude Code version is shown in the popover after the first capture.

## Build, test, and run

```bash
swift test
./script/build_and_run.sh --verify
```

The run script builds a real menu-bar-only app bundle at:

```text
dist/Claude Gauge.app
```

Other supported modes:

```bash
./script/build_and_run.sh
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

## Install and launch at login

Install the optimized app to `~/Applications`, register its launch agent, install the capture helper, and configure Claude Code's status line:

```bash
./script/install.sh
```

The installer:

1. Installs and verifies `Claude Gauge.app` plus `~/Library/LaunchAgents/com.joar.claudegauge.plist`.
2. Copies the capture helper to `~/.claude/claude-gauge/capture`.
3. Adds this entry to `~/.claude/settings.json`:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "/Users/you/.claude/claude-gauge/capture"
     }
   }
   ```

The installer fails closed for empty, unreadable, malformed, or foreign statusLine settings. It never rewrites them, and restores any previous app/launch-agent installation if setup fails.

After installation, restart any existing Claude Code sessions (or start a new one) and send one message. Sessions already running during installation may not load the new statusLine command. Anthropic populates `rate_limits` after the first API response in the restarted session.

### Existing custom status line

If you already use a custom status line, keep it and feed the same stdin JSON to Claude Gauge from your statusline command. One shell pattern is:

```bash
CAPTURE="$(swift build --configuration release --show-bin-path)/claude-gauge-capture"
"$CAPTURE" install-helper
```

Then prefix your existing `statusLine.command` with:

```bash
tee >(~/.claude/claude-gauge/capture >/dev/null) | your-statusline-command
```

The exact wrapper depends on how your existing command reads stdin; Claude Gauge deliberately refuses to overwrite it automatically.

If you later uninstall Claude Gauge, remove that tee segment from your custom statusLine command manually. The uninstaller refuses to delete the helper while a custom status line still references it.

### Diagnostics

```bash
~/.claude/claude-gauge/capture status
```

To remove the app, launch agent, and exact user-level statusLine entry installed by Claude Gauge:

```bash
./script/uninstall.sh
```

The helper and cache are intentionally preserved because project-local Claude settings can also reference them, and the uninstaller cannot safely discover every project. If any custom, foreign, malformed, or unreadable user statusLine remains, uninstall also fails closed. Symlink-managed user settings are updated through their resolved target without replacing the symlink. Remove or detach conflicting settings, then rerun.

After checking that no user or project status line references Claude Gauge, you can explicitly purge the preserved files:

```bash
rm -rf ~/.claude/claude-gauge
```

## Architecture

- `ClaudeGaugeCore/` — normalized usage models, official statusline JSON decoding, cache format, formatting, and settings mutation
- `ClaudeGaugeCapture/` — fast stdin capture binary and statusLine install/uninstall commands
- `ClaudeGauge/App/` — SwiftUI menu bar scene
- `ClaudeGauge/Stores/` — refresh lifecycle and stale-data preservation
- `ClaudeGauge/Services/` — cache reader and installation status
- `ClaudeGauge/Views/` — status label, popover, usage rings, and data-age indicator

Cache updates are serialized with a local file lock and use atomic replacement. Concurrent sessions reconcile by reset timestamp and used percentage so an older session cannot regress a newer window. The app polls the complete cache every ten seconds, avoiding watcher lifecycle races.

## Research basis

Claude Gauge relies only on Anthropic's documented statusline interface:

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
