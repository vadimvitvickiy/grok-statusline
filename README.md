# grok-statusline

A readable three-line status line for [Grok Build](https://x.ai/cli). It shows the model, reasoning effort, how much of the context window is used and left, git and session details, the prompt-cache hit rate, and the session cost.

It is a single Bash script, in the same layout as [claude-statusline](https://github.com/vadimvitvickiy/claude-statusline). It reads the JSON Grok already sends to status line commands, so it makes no network calls and needs nothing beyond `jq` and `git`.

## What it shows

| Line | Segment | Details |
|-|-|-|
| 1 | `MODEL` | Model name, with `1M` when the context window holds at least a million tokens |
| 1 | `EFFORT` | Reasoning effort, when the model reports one |
| 1 | `CONTEXT` | Percentage used and left, and tokens in the live window out of the window size |
| 1 | `BRANCH` | Checked-out branch, or the short commit hash when HEAD is detached |
| 1 | `WORKTREE` | Shown only inside a linked worktree |
| 2 | `FOLDER` | Current working directory name |
| 2 | `SESSION` | Time since this process attached the session. A resumed session counts from the resume |
| 2 | `TURN` | Elapsed time of the turn in flight. Hidden between turns |
| 2 | `CACHE` | Share of this session's input tokens read from the prompt cache, after the first model call |
| 3 | `COST` | Session cost. Hidden below half a cent, so a new session does not show `$0.00` |

Every kind of value has its own color. The context percentage is green, orange from 50% used, and red from 80% used.

Before Grok has reported a context count, the context segment reads `waiting for first response`. A token count Grok omits stays blank. The session totals only grow, so they are never shown as a fraction of the live window.

Grok re-runs the script when the session changes, and continuously while a turn is running. An idle session does not re-run it, so the session age holds still until the next change.

## Requirements

- Grok Build.
- Bash, `jq` and `git`. The cost figure is formatted with `awk`, which ships with macOS and typical Linux systems.
- A terminal with 24-bit color support, such as Ghostty, cmux, iTerm2, WezTerm or Kitty.

The script is tested on macOS. Grok's command status line is documented for macOS and Linux.

## Installation

1. Download the script into your Grok directory and make it executable:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/vadimvitvickiy/grok-statusline/main/statusline.sh -o ~/.grok/statusline.sh
   chmod +x ~/.grok/statusline.sh
   ```

2. Point Grok at it by adding this to `~/.grok/config.toml`:

   ```toml
   [ui.status_line]
   type = "command"
   command = "~/.grok/statusline.sh"
   ```

   If the file already has other settings, add only the `[ui.status_line]` table. Grok reads this table from your own config. A repository cannot turn the row on.

3. Restart Grok. The row appears once a session is active. It stays hidden on the welcome screen and while a subagent view is open full screen.

A change to `config.toml` is read at startup. A change to the script file applies the next time Grok runs it.

To update, run the `curl` command from step 1 again.

## Light and dark themes

The colors are tuned separately for light and dark backgrounds. On macOS the script follows the system appearance. If your terminal theme does not follow the system, or you are on Linux, choose the palette explicitly:

```toml
[ui.status_line]
type = "command"
command = "GROK_STATUSLINE_THEME=dark ~/.grok/statusline.sh"
```

## Customization

The top of `statusline.sh` holds the settings most people change:

- `WARNING_PERCENT` and `ALERT_PERCENT` set when context usage turns orange and red.
- The `BLUE`, `VIOLET`, `GREEN` and other color constants are `R;G;B` values for each palette.
- The three `join_segments` calls at the bottom set which segments appear on each line and in what order.

To test a change without waiting for Grok, pipe sample data into the script:

```bash
echo '{"model":{"display_name":"Grok 4.7"},"effort":{"level":"high"},"workspace":{"current_dir":"/tmp/demo","branch":"main"},"context_window":{"used_percentage":42,"context_tokens":84000,"context_window_size":200000}}' \
  | ~/.grok/statusline.sh
```

See the [Grok Build status line documentation](https://docs.x.ai/build/features/status-line) for every field available.

## Uninstall

Remove the `[ui.status_line]` table from `~/.grok/config.toml` and delete `~/.grok/statusline.sh`. Restart Grok.

## License

[MIT](LICENSE)
