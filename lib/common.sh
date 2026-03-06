#!/usr/bin/env bash

# Common library for ws-update
# Provides logging, error handling, and helper functions used by update.sh

# === Strict Error Handling ===
set -euo pipefail
IFS=$'\n\t'

# === Configuration ===
# Preserve WORKSPACE_ROOT if already set by the caller
if [[ -z "${WORKSPACE_ROOT:-}" ]]; then
  WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../" && pwd)"
fi

# Logging
LOG_DIR="${WS_LOG_DIR:-/tmp/ws-update}"
[[ ! -d "$LOG_DIR" ]] && mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_FILE:-$LOG_DIR/update-$(date +%Y%m%d_%H%M%S).log}"

# === Logging Functions ===
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" | tee -a "$LOG_FILE" >&2
}

log_success() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - SUCCESS: $1" | tee -a "$LOG_FILE"
}

log_warning() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: $1" | tee -a "$LOG_FILE"
}

begin_section() {
  echo "" | tee -a "$LOG_FILE"
  log "=== BEGIN: $1 ==="
}

end_section() {
  log "=== END: $1 ==="
  echo "" | tee -a "$LOG_FILE"
}

die() {
  local message="$1"
  local exit_code="${2:-1}"
  log_error "$message"
  log_error "Script terminated. Check log file: $LOG_FILE"
  exit "$exit_code"
}

# === Sudo Helpers ===
setup_sudo_askpass() {
  if [[ -n "${SUDO_ASKPASS:-}" ]]; then
    return 0
  fi

  log "Setting up secure SUDO_ASKPASS for the session..."

  # Create a restricted temporary directory
  local auth_dir
  auth_dir=$(mktemp -d /tmp/ws-update-auth-XXXXXX)
  chmod 700 "$auth_dir"
  export WS_SUDO_AUTH_DIR="$auth_dir"

  local pass_file="$auth_dir/.sp"
  local askpass_script="$auth_dir/askpass.sh"

  # Prompt for password once and store it
  stty -echo
  printf "Enter sudo password for %s (stored securely for this session): " "${USER:-$(whoami)}"
  read -r password
  stty echo
  printf "\n"

  echo "$password" > "$pass_file"
  chmod 600 "$pass_file"

  # Create the askpass script
  cat <<EOF > "$askpass_script"
#!/usr/bin/env bash
cat "$pass_file"
EOF
  chmod 700 "$askpass_script"

  export SUDO_ASKPASS="$askpass_script"
  # Pre-verify sudo access
  if ! sudo -A -v; then
    rm -rf "$auth_dir"
    die "Invalid sudo password provided"
  fi
}

require_sudo() {
  if ! sudo -n true 2>/dev/null; then
    setup_sudo_askpass
  fi
}

start_sudo_keepalive() {
  if [[ -z "${SUDO_KEEPALIVE_PID:-}" ]]; then
    log "Starting sudo keepalive background process..."

    # Refresh sudo credential every 50 seconds.
    # The default sudo timeout is 5-15 min; 50s keeps it well within range.
    (
      while true; do
        if [[ -n "${SUDO_ASKPASS:-}" ]]; then
          sudo -A -v 2>/dev/null || true
        else
          sudo -n -v 2>/dev/null || true
        fi
        sleep 50
      done
    ) &

    export SUDO_KEEPALIVE_PID=$!
    log "Sudo keepalive started (PID: $SUDO_KEEPALIVE_PID)"
  fi
}

stop_sudo_keepalive() {
  if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
    log "Stopping sudo keepalive process..."
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    unset SUDO_KEEPALIVE_PID
  fi
}

# === Pre-flight Checks ===
check_internet() {
  curl -sf --max-time 5 --head https://connectivity-check.ubuntu.com/ >/dev/null 2>&1
}

# === Cleanup and Error Handling ===
_ws_update_cleanup() {
  local exit_code=$?
  stop_sudo_keepalive
  
  if [[ -n "${WS_SUDO_AUTH_DIR:-}" && -d "$WS_SUDO_AUTH_DIR" ]]; then
    rm -rf "$WS_SUDO_AUTH_DIR"
  fi

  if [[ $exit_code -ne 0 ]]; then
    echo
    log_error "==========================================="
    log_error "Script execution failed with exit code: $exit_code"
    log_error "==========================================="
    log_error "Check the log file: $LOG_FILE"
    log_error "==========================================="
  fi
  exit "$exit_code"
}

_ws_update_interrupt_handler() {
  echo
  log "Script interrupted by user (Ctrl+C)"
  exit 130
}

setup_error_handling() {
  trap _ws_update_cleanup EXIT
  trap _ws_update_interrupt_handler INT TERM
}

# === Version Tracking ===
record_tool_versions() {
  begin_section "Tool Versions"

  # Tools whose --version produces multi-line output
  local multiline_tools=" bash php "
  local tools=("bash" "git" "curl" "wget" "docker" "docker-compose" "node" "npm" "php" "composer" "python3" "pip3")

  for tool in "${tools[@]}"; do
    command -v "$tool" &>/dev/null || continue
    if [[ "$multiline_tools" == *" $tool "* ]]; then
      log "$tool: $("$tool" --version 2>/dev/null | head -n1)"
    else
      log "$tool: $("$tool" --version 2>/dev/null || echo 'unknown')"
    fi
  done

  # System information
  if [[ -f /etc/os-release ]]; then
    log "OS: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
  fi
  log "Kernel: $(uname -r)"
  log "Architecture: $(uname -m)"

  end_section "Tool Versions"
}
