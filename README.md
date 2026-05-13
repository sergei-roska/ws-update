# ws-update

Automated update workflow for a Linux-based web development environment.

This repository provides a single entrypoint script, `update.sh`, that updates common system and developer tooling in a consistent, logged, and failure-aware way.

## What this script updates

`update.sh` runs update/maintenance steps for tools that are installed on the machine:

- System packages (`apt update`, `apt upgrade`)
- Snap packages (`snap refresh`)
- Flatpak applications/remotes with repair flow
- Docker image cleanup
- Composer self/global updates
- Node.js ecosystem (`nvm`, `npm`, optional `yarn` and `pnpm`)
- Python tooling (`pipx` or user-scoped `pip3`)
- DDEV
- Lando
- Terminus
- Homebrew (if installed)
- Final system cleanup (`apt autoremove`, `apt autoclean`)

If a tool is not installed, its section is skipped.

## Repository structure

- `update.sh` — main update orchestrator
- `lib/common.sh` — logging, traps/error handling, sudo helpers, version reporting
- `lib/flatpak.sh` — Flatpak-specific remote/update/GPG-repair helpers

## Requirements

- Bash 5+
- Ubuntu/Debian-compatible `apt` environment for system package steps
- `sudo` access for privileged operations when not using dry-run
- Internet connection for real update runs

Optional tools are detected at runtime and only updated if available.

## Usage

From repository root:

```bash path=null start=null
chmod +x update.sh
./update.sh
```

### Dry-run mode

Preview changes without applying them:

```bash path=null start=null
./update.sh --dry-run
```

In dry-run mode, mutating commands are not executed. The script logs what would be run and still prints a section-by-section summary.

### Help

```bash path=null start=null
./update.sh --help
```

## Execution flow

1. Loads shared libraries from `lib/`.
2. Configures traps and logging.
3. Runs preflight checks (real mode only): internet check, sudo verification, sudo keepalive.
4. Executes update sections in order.
5. Records post-run tool versions.
6. Prints summary and final next steps.

## Logging

Logs are written to:

- default: `/tmp/ws-update/`
- file format: `update-YYYYmmdd_HHMMSS.log`

The active log file path is printed at startup and in summary output.

You can override log directory:

```bash path=null start=null
WS_LOG_DIR=/custom/path ./update.sh
```

## Result summary

Each section records a result status (for example `OK`, `FAILED`, or dry-run markers) and prints it at the end of execution.

This helps quickly identify which subsystem needs attention without reading the full log first.

## Safety and failure behavior

- Strict shell mode is enabled (`set -euo pipefail`).
- Errors are trapped and logged with context.
- `sudo` keepalive background process is started only in real mode and is cleaned up on normal exit, error, or interruption.
- Flatpak includes recovery flow for GPG/signature-related failures.

## Common examples

Run full update:

```bash path=null start=null
./update.sh
```

Preview planned actions:

```bash path=null start=null
./update.sh --dry-run
```

Write logs to a custom directory:

```bash path=null start=null
WS_LOG_DIR="$HOME/ws-update-logs" ./update.sh --dry-run
```

## Troubleshooting

### Unknown option error

Use:

```bash path=null start=null
./update.sh --help
```

### Permission/sudo issues

- Ensure your user can run `sudo`.
- Re-run in dry-run to verify flow without privileged changes:

```bash path=null start=null
./update.sh --dry-run
```

### Section failed

1. Check summary output for failed section name.
2. Open the log file printed by the script.
3. Re-run after fixing local issue (network, package manager lock, credentials, broken repo metadata, etc.).

### Flatpak-related errors

The script attempts automatic Flatpak GPG/remote repair. If it still fails, review the Flatpak section in the log for exact command output.

## Notes

- This script is intended for developer workstation maintenance, not production servers.
- Always run `--dry-run` first if you want to preview impact before applying updates.
