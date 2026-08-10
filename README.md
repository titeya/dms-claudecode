# Claude Code Usage

A [DMS (Dank Material Shell)](https://github.com/AvengeMedia/DankMaterialShell) plugin that monitors your Claude Code subscription usage directly from the taskbar.

![Screenshot](screenshot.png)

## Features

- **Taskbar pill** with circular progress ring showing 5-hour rate limit utilization
- **Detailed popout** with:
  - 5-hour and 7-day rate window utilization with countdown timers
  - Stale-data warning when the usage API cannot be reached — the pill dims and adds `?`, and the popout says how old the numbers are and what to do about it (e.g. `3h 40m old · Claude Code login expired - run claude once`), instead of presenting cached numbers as live
  - Refresh button in the popout header for an immediate fetch that ignores the cache — after fixing an expired login you see the real numbers straight away instead of waiting out the refresh interval
  - Pacing indicator showing whether you're over or under a linear burn rate for each window (e.g. "6% over pace", "25% under pace")
  - Per-model weekly limits under the 7-day ring — claude.ai gives some models their own weekly cap, so the all-models ring can sit at 71% while a single model is at 6%
  - Token consumption breakdown (today, the current rate limit week, calendar month). The week totals cover the seven days the 7-day ring measures, which start when the limit last reset, not Monday - the card says which day they start from
  - Estimated API cost per period (today, week, calendar month) with automatic pricing from [LiteLLM](https://github.com/BerriAI/litellm)
  - Weekly activity bar chart (Monday–Sunday) with interactive hover tooltips (token count + cost)
  - Per-model token usage for the current rate limit week with dynamic model family detection
  - All-time session and message statistics
- **Profile breakdown** — per-profile token/cost stats with a hybrid profile selector (tabs for up to 4 profiles, dropdown for more). Profiles are discovered automatically from:
  - `~/.claude` (the `default` profile)
  - [CCS](https://github.com/kaitranntt/ccs) instances in `~/.ccs/instances/`
  - [claude-code-profiles](https://github.com/felipeadeildo/claude-code-profiles) profiles in `~/.ccp/profiles/*.env` (the `CLAUDE_CONFIG_DIR` declared in each `.env` is used)
  - Any directory you add manually under **Custom Profiles** in the plugin settings
  - Profile overlay on the daily activity chart: grey bars show total usage, colored bars show the selected profile's share
  - Tooltip shows both total and per-profile token counts when a profile is selected
- **Automatic subscription detection** via the Anthropic OAuth API
- **Automatic token renewal** — the ~12h OAuth access token is refreshed with the stored refresh token when it expires, so the widget keeps working through the days you never launch Claude Code
- **Dynamic model pricing** — new Anthropic model families are detected automatically, no code changes needed
- **Currency support** — costs displayed in EUR for French locale, USD otherwise (exchange rate from ECB via [Frankfurter](https://www.frankfurter.app/))
- **Configurable refresh interval** (2 to 15 minutes)
- **Localization support** (English and French)

## Requirements

- [DMS Shell](https://github.com/AvengeMedia/DankMaterialShell)
- [jq](https://jqlang.github.io/jq/) (JSON processor)
- An active [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installation with OAuth credentials

## Installation

### From the DMS Plugin Registry

```
dms plugins install claudeCodeUsage
```

Or browse the plugin list in DMS Settings (`Mod + ,` > Plugins).

### Manual

Clone this repository into your DMS plugins directory:

```bash
git clone https://github.com/titeya/dms-claudecode \
  ~/.config/DankMaterialShell/plugins/claudeCodeUsage
```

Then restart DMS.

## Configuration

Open DMS Settings (`Mod + ,` > Plugins > Claude Code Usage) to adjust the refresh interval,
toggle pacing indicators, and register custom profiles.

### Custom Profiles

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

## How It Works

The plugin runs a lightweight bash script at the configured interval that:

1. Reads your OAuth token from `~/.claude/.credentials.json`, and renews it with the stored refresh token when it has expired (the same `refresh_token` grant Claude Code itself uses)
2. Queries the Anthropic usage API for current rate limit status
3. Scans `<config dir>/projects/` for every discovered profile (see above) for token consumption statistics — each profile is processed in parallel
4. Fetches model pricing from LiteLLM and USD/EUR exchange rate from ECB (cached daily in `~/.claude/pricing-cache.json`)

API usage responses are cached for 90 seconds (`~/.claude/usage-cache.json`) to avoid rate limiting; the popout refresh button skips that cache. If a fetch fails the cached numbers are still shown, but they are labelled with their age and the reason the fetch failed — a login that not even the refresh token can save (run `claude` once), a rate limit, or no connection.

All data stays local. Network requests are limited to the official Anthropic API (usage), the Claude OAuth token endpoint (only when the access token has to be renewed), GitHub (LiteLLM pricing, once/day), and Frankfurter (exchange rate, once/day).

## License

[MIT](LICENSE)
