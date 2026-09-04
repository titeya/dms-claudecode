# AI Usage

A [DMS (Dank Material Shell)](https://github.com/AvengeMedia/DankMaterialShell) plugin that monitors your Claude and ChatGPT/Codex subscription usage directly from the taskbar. Both are optional and independently toggled — install this for either one, or both, and whichever isn't set up simply stays out of the way.

![Screenshot](screenshot.png)

## Features

- **Taskbar pill** with a circular progress ring per enabled Source (Claude, ChatGPT), each showing its nearest-to-reset rate window
- **Pacing indicator** on both Sources, showing whether you're over or under a linear burn rate for each window (e.g. "6% over pace", "25% under pace")
- **Detailed popout**, one tab per Source:
  - **Claude**: 5-hour and 7-day rate window utilization with countdown timers and pacing
  - **ChatGPT**: primary and secondary rate windows (lengths reported by the API) with countdown timers and pacing
  - Token consumption breakdown (today, calendar week, calendar month) for both Sources
  - Weekly activity bar chart (Monday–Sunday) with interactive hover tooltips, for both Sources
  - Per-model token usage for the current calendar week with dynamic model family detection, for both Sources
  - Estimated API cost per period (Claude only, automatic pricing from [LiteLLM](https://github.com/BerriAI/litellm) — no equivalent public price list exists for Codex/ChatGPT)
  - All-time session and message statistics (Claude)
- **Account breakdown**, per Source:
  - **Claude profiles** — a hybrid selector (tabs for up to 4, dropdown for more), discovered automatically from:
    - `~/.claude` (the `default` profile)
    - [CCS](https://github.com/kaitranntt/ccs) instances in `~/.ccs/instances/`
    - [claude-code-profiles](https://github.com/felipeadeildo/claude-code-profiles) profiles in `~/.ccp/profiles/*.env` (the `CLAUDE_CONFIG_DIR` declared in each `.env` is used)
    - Any directory you add manually under **Custom Profiles** in the plugin settings
  - **ChatGPT accounts** — any account you add manually under **Custom ChatGPT Accounts** in the plugin settings
  - Profile/account overlay on each Source's daily activity chart: grey bars show total usage, colored bars show the selected profile/account's share
- **Login action** when a Source's credentials are missing or expired — a card in that Source's popout starts `claude auth login --claudeai` (Claude) or a `codex` refresh (ChatGPT), then re-fetches on completion
- **Graceful degradation**: a Source with no binary installed hides entirely; one with a missing/expired token stays visible with a login card instead of silently showing zeros
- **Automatic subscription detection** via the Anthropic OAuth API (Claude) and the ChatGPT backend (Codex CLI's stored OAuth token)
- **Dynamic model pricing** — new Anthropic model families are detected automatically, no code changes needed
- **Currency support** — costs displayed in EUR for French locale, USD otherwise (exchange rate from ECB via [Frankfurter](https://www.frankfurter.app/))
- **Configurable refresh interval** (2 to 15 minutes)
- **Localization support** (English and French)

## Requirements

- [DMS Shell](https://github.com/AvengeMedia/DankMaterialShell)
- [jq](https://jqlang.github.io/jq/) (JSON processor)

Neither AI tool is mandatory — install and enable the Sources you actually use:

- **Claude**: an active [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installation with OAuth credentials
- **ChatGPT**: an active [Codex CLI](https://github.com/openai/codex) installation with OAuth credentials

A Source with no binary on `PATH` is detected automatically and hidden from the pill/popout; it doesn't need to be disabled by hand.

## Installation

### From the DMS Plugin Registry

```
dms plugins install aiUsage
```

Or browse the plugin list in DMS Settings (`Mod + ,` > Plugins).

### Manual

Clone this repository into your DMS plugins directory:

```bash
git clone https://github.com/titeya/dms-claudecode \
  ~/.config/DankMaterialShell/plugins/aiUsage
```

Then restart DMS.

## Configuration

Open DMS Settings (`Mod + ,` > Plugins > AI Usage) to adjust the refresh interval, toggle
pacing indicators, enable/disable each Source, and register custom profiles/accounts.

### Custom Claude Profiles

If you use a profile manager the plugin doesn't detect automatically, add it under
**Custom Profiles** with a name and a config directory path:

| Name | Config directory |
|------|------------------|
| `work` | `~/.ccp/data/work` |

The path is a `CLAUDE_CONFIG_DIR` — the folder that contains `projects/`, i.e. whatever
`~/.claude` is for the default profile. The plugin reads usage from `<path>/projects/`
and, when present, `<path>/.credentials.json` so rate limits are tracked per profile too.

Entries whose `projects/` folder doesn't exist are ignored, and a name already claimed by
an auto-detected profile is skipped.

### Custom ChatGPT Accounts

Add additional accounts under **Custom ChatGPT Accounts** the same way, with a name and an
auth directory (the folder containing `auth.json`, i.e. whatever `~/.codex` is by default).

## How It Works

The plugin runs two lightweight bash scripts on the configured refresh interval, one per
Source:

**Claude** (`get-claude-usage`):
1. Reads your OAuth token from `~/.claude/.credentials.json`
2. Queries the Anthropic usage API for current rate limit status
3. Scans `<config dir>/projects/` for every discovered profile (see above) for token consumption statistics — each profile is processed in parallel
4. Fetches model pricing from LiteLLM and USD/EUR exchange rate from ECB (cached daily in `~/.claude/pricing-cache.json`)

**ChatGPT** (`get-chatgpt-usage`):
1. Reads your OAuth token from `~/.codex/auth.json` (or a custom account's `auth.json`)
2. Queries the ChatGPT backend (`wham/usage`) for current rate limit status across the primary and secondary windows
3. Scans `<account dir>/sessions/**/*.jsonl` for every discovered account for token consumption statistics

Both scripts detect whether their binary (`claude`/`codex`) is present before doing any
work, so a Source with nothing installed short-circuits to "not installed" instead of
attempting a fetch.

Claude's usage API response is cached for 90 seconds (`~/.claude/usage-cache.json`) to
avoid rate limiting, with stale fallback on errors. ChatGPT's usage call has no cache —
it's a single lightweight request per account per refresh.

All data stays local. Network requests are limited to the official Anthropic API (usage),
the ChatGPT backend (usage), GitHub (LiteLLM pricing, once/day), and Frankfurter (exchange
rate, once/day).

## License

[MIT](LICENSE)
