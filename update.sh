#!/usr/bin/env bash

# Update Script for Web Development Environment
# Updates all installed development tools and packages

# === Load Common Library ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$SCRIPT_DIR"

# Source the common library first - this sets strict mode and IFS
source "$WORKSPACE_ROOT/lib/common.sh"

# Source shared Flatpak library
source "$WORKSPACE_ROOT/lib/flatpak.sh"
# === CLI Options ===
DRY_RUN=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [--dry-run] [--help]

Options:
  --dry-run   Show what would be changed without executing mutating commands.
  --help      Show this help message and exit.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

run_step() {
  local label="$1"
  shift
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[DRY-RUN] $label: $*"
    return 0
  fi
  "$@"
}

# Setup error handling
setup_error_handling

# === Result tracking ===
declare -A UPDATE_RESULTS
mark_result() { UPDATE_RESULTS["$1"]="$2"; }

# Export mode for shared libraries
export DRY_RUN

# === Pre-flight checks ===
if [[ "$DRY_RUN" -eq 1 ]]; then
  log "🧪 DRY-RUN mode enabled: no changes will be applied"
else
  if ! check_internet; then
    die "No internet connectivity. Cannot proceed with updates."
  fi

  require_sudo
  start_sudo_keepalive
fi

log "🔄 Starting web development environment update..."
log "Log file: $LOG_FILE"

# === System Updates ===
if command -v apt &>/dev/null; then
  begin_section "System Packages"
  log "📦 Updating system packages..."
  if run_step "System package index update" sudo apt update && run_step "System package upgrade" sudo apt upgrade -y; then
    run_step "System package autoremove" sudo apt autoremove -y
    run_step "System package autoclean" sudo apt autoclean
    mark_result "System packages" "OK"
    log_success "System packages updated"
  else
    mark_result "System packages" "FAILED"
    log_warning "System package update had issues"
  fi
  end_section "System Packages"
fi

# === Snap Updates ===
if command -v snap &>/dev/null; then
  begin_section "Snap"
  log "📦 Updating Snap packages..."
  if run_step "Snap refresh" sudo snap refresh; then
    mark_result "Snap" "OK"
    log_success "Snap packages updated successfully"
  else
    mark_result "Snap" "FAILED"
    log_warning "Some Snap packages failed to update (check log for details)"
  fi
  end_section "Snap"
fi

# === Flatpak Updates with Robust GPG Handling ===
if command -v flatpak &>/dev/null; then
  begin_section "Flatpak"

  if ! ensure_flathub_remote; then
    mark_result "Flatpak" "FAILED"
    log_error "Failed to ensure Flathub remote, skipping Flatpak updates"
  else
    if ! attempt_flatpak_update; then
      log_warning "Initial Flatpak update failed, attempting GPG repair..."

      if repair_flatpak_gpg; then
        mark_result "Flatpak" "OK (after GPG repair)"
        log_success "Flatpak GPG repair and update completed"
      else
        mark_result "Flatpak" "FAILED"
        log_error "Flatpak GPG repair failed"
        die "Flatpak update failed even after attempting GPG repair" 1
      fi
    else
      log "Cleaning up unused Flatpak packages..."
      run_step "Flatpak uninstall unused (user)" flatpak uninstall --user --unused -y || true
      if sudo -n true 2>/dev/null; then
        run_step "Flatpak uninstall unused (system)" flatpak uninstall --system --unused -y || true
      fi
      mark_result "Flatpak" "OK"
      log_success "Flatpak applications updated successfully"
    fi
  fi

  end_section "Flatpak"
fi

# === Docker Cleanup ===
if command -v docker &>/dev/null; then
  begin_section "Docker"
  log "🐳 Pruning unused Docker images..."
  if run_step "Docker image prune" docker image prune -f; then
    mark_result "Docker" "OK"
    log_success "Docker cleanup completed"
  else
    mark_result "Docker" "FAILED"
    log_warning "Docker cleanup failed"
  fi
  end_section "Docker"
fi

# === PHP Composer Updates ===
if command -v composer &>/dev/null; then
  begin_section "Composer"
  log "🎼 Updating Composer..."
  if run_step "Composer self-update" composer self-update; then
    mark_result "Composer" "OK"
    log_success "Composer updated"
  else
    mark_result "Composer" "FAILED"
    log_warning "Composer self-update failed"
  fi

  if [[ -f "$HOME/.config/composer/composer.json" ]]; then
    run_step "Composer global update" composer global update || log_warning "Composer global update failed"
  fi
  end_section "Composer"
fi

# === Node.js Updates ===
if [[ -d "$HOME/.nvm" ]]; then
  begin_section "Node.js"
  log "🟢 Updating Node.js and npm packages..."

  export NVM_DIR="$HOME/.nvm"
  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    # shellcheck source=/dev/null
    . "$NVM_DIR/nvm.sh"
  fi

  if command -v nvm &>/dev/null; then
    # Only install if not already on the latest LTS
    latest_lts=$(nvm version-remote --lts)
    current=$(nvm current)
    if [[ "$current" != "$latest_lts" ]]; then
      log "Current Node $current differs from latest LTS $latest_lts, upgrading..."
      run_step "NVM install latest LTS" nvm install --lts --reinstall-packages-from="$current"
      run_step "NVM set default alias" nvm alias default "$latest_lts"
    else
      log "Already on latest LTS ($current), skipping install"
    fi
    mark_result "Node.js" "OK ($latest_lts)"
  else
    mark_result "Node.js" "FAILED"
    log_warning "nvm is not available, skipped Node.js LTS update"
  fi

  run_step "npm global update" npm update -g || log_warning "npm global update failed"

  # Update yarn and pnpm if installed
  if command -v yarn &>/dev/null; then
    run_step "Install latest yarn" npm install -g yarn@latest || log_warning "yarn update failed"
  fi
  if command -v pnpm &>/dev/null; then
    run_step "Install latest pnpm" npm install -g pnpm@latest || log_warning "pnpm update failed"
  fi

  if [[ "${UPDATE_RESULTS["Node.js"]}" == FAILED ]]; then
    log_warning "Node.js environment update incomplete"
  else
    log_success "Node.js environment updated"
  fi
  end_section "Node.js"
fi

# === Python Updates ===
if command -v pipx &>/dev/null; then
  begin_section "Python (pipx)"
  log "🐍 Updating pipx packages..."
  if run_step "pipx upgrade-all" pipx upgrade-all; then
    mark_result "Python (pipx)" "OK"
    log_success "pipx packages updated"
  else
    mark_result "Python (pipx)" "FAILED"
    log_warning "pipx upgrade-all failed"
  fi
  end_section "Python (pipx)"
fi

if command -v pip3 &>/dev/null; then
  begin_section "Python (pip3)"
  log "🐍 Updating user-scoped pip packages..."
  run_step "pip3 upgrade pip (user)" pip3 install --upgrade pip --user || log_warning "Failed to upgrade pip"

  outdated_packages=$(pip3 list --user --outdated --format=columns 2>/dev/null | tail -n +3 | awk '{print $1}' | tr '\n' ' ')
  if [[ -n "$outdated_packages" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "[DRY-RUN] Would update Python packages: $outdated_packages"
    else
      echo "$outdated_packages" | xargs -n1 pip3 install --user -U >>"$LOG_FILE" 2>&1 || true
      log "Updated Python packages: $outdated_packages"
    fi
  else
    log "No outdated user Python packages"
  fi
  mark_result "Python (pip3)" "OK"
  log_success "Python packages updated"
  end_section "Python (pip3)"
fi

# === DDEV Updates ===
if command -v ddev &>/dev/null; then
  begin_section "DDEV"
  log "⚙️ Updating DDEV..."
  if [[ "$DRY_RUN" -eq 1 ]]; then
    mark_result "DDEV" "DRY-RUN"
    log "[DRY-RUN] Would download and run DDEV installer"
  else
    ddev_installer=$(mktemp /tmp/ddev-install-XXXXXX.sh)
    if curl -fsSL https://ddev.com/install.sh -o "$ddev_installer"; then
      if bash "$ddev_installer" 2>>"$LOG_FILE"; then
        mark_result "DDEV" "OK"
        log_success "DDEV updated"
      else
        mark_result "DDEV" "FAILED"
        log_warning "DDEV install script failed"
      fi
    else
      mark_result "DDEV" "FAILED"
      log_warning "Failed to download DDEV installer"
    fi
    rm -f "$ddev_installer"
  fi
  end_section "DDEV"
fi

# === Lando Updates ===
if command -v lando &>/dev/null; then
  begin_section "Lando"
  log "🛠️ Updating Lando..."
  if [[ "$DRY_RUN" -eq 1 ]]; then
    mark_result "Lando" "DRY-RUN"
    log "[DRY-RUN] Would download and run Lando installer"
  else
    lando_installer=$(mktemp /tmp/setup-lando-XXXXXX.sh)
    if curl -fsSL https://get.lando.dev/setup-lando.sh -o "$lando_installer"; then
      chmod +x "$lando_installer"
      if bash "$lando_installer" --yes 2>>"$LOG_FILE"; then
        mark_result "Lando" "OK"
        log_success "Lando updated"
      else
        mark_result "Lando" "FAILED"
        log_warning "Lando install script failed"
      fi
    else
      mark_result "Lando" "FAILED"
      log_warning "Failed to download Lando installer"
    fi
    rm -f "$lando_installer"
  fi
  end_section "Lando"
fi

# === Terminus Updates ===
if command -v terminus &>/dev/null; then
  begin_section "Terminus"
  log "🧩 Updating Terminus..."
  if run_step "Terminus self:update" terminus self:update; then
    mark_result "Terminus" "OK"
    log_success "Terminus updated"
  else
    mark_result "Terminus" "FAILED"
    log_warning "Terminus self:update failed"
  fi
  end_section "Terminus"
fi

# === Homebrew Updates (if installed) ===
if command -v brew &>/dev/null; then
  begin_section "Homebrew"
  log "🍺 Updating Homebrew..."
  if run_step "Homebrew update" brew update && run_step "Homebrew upgrade" brew upgrade; then
    run_step "Homebrew cleanup" brew cleanup
    mark_result "Homebrew" "OK"
    log_success "Homebrew updated"
  else
    mark_result "Homebrew" "FAILED"
    log_warning "Homebrew update had issues"
  fi
  end_section "Homebrew"
fi

# === Final Cleanup ===
begin_section "Cleanup"
log "🧹 Final cleanup..."
if command -v apt &>/dev/null; then
  run_step "apt autoremove" sudo apt autoremove -y
  run_step "apt autoclean" sudo apt autoclean
fi
end_section "Cleanup"

# Record versions of key tools after update
record_tool_versions

# === Summary ===
log "📋 Summary:"
log "  Log file: $LOG_FILE"
for section in "${!UPDATE_RESULTS[@]}"; do
  log "  $section: ${UPDATE_RESULTS[$section]}"
done

log ""
log "🔄 Next steps:"
if [[ "$DRY_RUN" -eq 1 ]]; then
  log "  1. Re-run without --dry-run to apply updates"
  log "  2. Review the dry-run output in the log"
else
  log "  1. Restart your terminal to load updates"
  log "  2. Test your development tools"
fi

# Stop sudo keepalive
stop_sudo_keepalive

trap - ERR

echo ""
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "🧪 Dry-run complete. No changes were applied. Log: $LOG_FILE"
else
  echo "🎉 Environment update complete! Check the log for details: $LOG_FILE"
fi
