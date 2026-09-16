#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
USER_NAME="$(id -un)"
SCRATCH=""

fail() {
  printf 'verify-nix-config: %s\n' "$*" >&2
  exit 1
}

require_repo() {
  [ -n "$REPO_ROOT" ] || fail "run from the nix-config checkout"
  [ -f "$REPO_ROOT/flake.nix" ] || fail "flake.nix is missing"
  [ -f "$REPO_ROOT/justfile" ] || fail "justfile is missing"
  cd "$REPO_ROOT"
}

require_commands() {
  local command_name
  for command_name in nix just nh jq git; do
    command -v "$command_name" >/dev/null 2>&1 || fail "missing command: $command_name"
  done
}

resolve_host() {
  local candidate configured_hostname local_hostname hosts_json

  if [ -n "${VERIFY_HOST:-}" ]; then
    nix eval --raw ".#darwinConfigurations.${VERIFY_HOST}.config.networking.hostName" >/dev/null
    printf '%s\n' "$VERIFY_HOST"
    return
  fi

  [ "$(uname -s)" = "Darwin" ] || fail "automatic host resolution currently supports Darwin; set VERIFY_HOST"
  local_hostname="$(scutil --get LocalHostName)"
  hosts_json="$(nix eval --json .#darwinConfigurations --apply builtins.attrNames)"

  while IFS= read -r candidate; do
    configured_hostname="$(nix eval --raw ".#darwinConfigurations.${candidate}.config.networking.hostName" 2>/dev/null || true)"
    if [ "$configured_hostname" = "$local_hostname" ]; then
      printf '%s\n' "$candidate"
      return
    fi
  done < <(printf '%s' "$hosts_json" | jq -r '.[]')

  fail "no darwinConfigurations entry matches LocalHostName=$local_hostname; set VERIFY_HOST"
}

link_state() {
  local path="$1"
  printf '%s\t' "$path"
  if [ -L "$path" ]; then
    printf 'symlink\t%s\n' "$(readlink "$path")"
  elif [ -e "$path" ]; then
    printf 'present\n'
  else
    printf 'absent\n'
  fi
}

snapshot_links() {
  link_state /run/current-system
  link_state /nix/var/nix/profiles/system
  link_state "$HOME/.local/state/nix/profiles/home-manager"
  link_state "$HOME/.local/state/home-manager/gcroots/current-home"
  link_state "/etc/profiles/per-user/$USER_NAME"
}

doctor_core() {
  require_repo
  require_commands

  HOST_ATTR="$(resolve_host)"
  HOME_DRV="$(nix eval --raw ".#homeConfigurations.${HOST_ATTR}.config.home.activationPackage.drvPath")"
  SYSTEM_HOME_DRV="$(nix eval --raw ".#darwinConfigurations.${HOST_ATTR}.config.home-manager.users.${USER_NAME}.home.activationPackage.drvPath")"
  PROFILE_DIR="$(nix eval --raw ".#homeConfigurations.${HOST_ATTR}.config.home.profileDirectory")"
  USE_USER_PACKAGES="$(nix eval --json ".#darwinConfigurations.${HOST_ATTR}.config.home-manager.useUserPackages")"
  LEGACY_PROFILE="$(nix eval --json ".#darwinConfigurations.${HOST_ATTR}.config.home-manager.enableLegacyProfileManagement")"

  [ "$HOME_DRV" = "$SYSTEM_HOME_DRV" ] || fail "Home activationPackage differs from the system Home result"
  [ "$USE_USER_PACKAGES" = "false" ] || fail "home-manager.useUserPackages must be false"
  [ "$LEGACY_PROFILE" = "true" ] || fail "home-manager.enableLegacyProfileManagement must be true"
  case "$PROFILE_DIR" in
    /etc/profiles/per-user/*) fail "Home profile still points at the system user package environment" ;;
  esac
}

print_doctor() {
  printf 'doctor=ok\n'
  printf 'host=%s\n' "$HOST_ATTR"
  printf 'user=%s\n' "$USER_NAME"
  printf 'home_drv=%s\n' "$HOME_DRV"
  printf 'system_home_drv=%s\n' "$SYSTEM_HOME_DRV"
  printf 'profile_dir=%s\n' "$PROFILE_DIR"
  printf 'useUserPackages=%s\n' "$USE_USER_PACKAGES"
  printf 'enableLegacyProfileManagement=%s\n' "$LEGACY_PROFILE"
}

cleanup_scratch() {
  if [ -n "$SCRATCH" ] && [ -e "$SCRATCH" ]; then
    rm -rf "$SCRATCH"
  fi
}

run_build() {
  local feature="$1"
  local command_label="$2"
  shift 2
  local command_status links_unchanged timestamp evidence_dir

  doctor_core
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  evidence_dir="${VERIFY_EVIDENCE_DIR:-${TMPDIR:-/tmp}/verify-nix-config-evidence/${timestamp}-${HOST_ATTR}-${feature}-$$}"
  mkdir -p "$evidence_dir"
  SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/verify-nix-config-scratch.XXXXXX")"
  trap cleanup_scratch EXIT INT TERM

  print_doctor > "$evidence_dir/doctor.txt"
  snapshot_links > "$evidence_dir/before-links.txt"
  git status --short > "$evidence_dir/working-tree.txt"
  {
    printf 'feature=%s\n' "$feature"
    printf 'host=%s\n' "$HOST_ATTR"
    printf 'user=%s\n' "$USER_NAME"
    printf 'git_revision=%s\n' "$(git rev-parse HEAD)"
    printf 'nix=%s\n' "$(nix --version)"
    printf 'nh=%s\n' "$(nh --version)"
    printf 'just=%s\n' "$(just --version)"
    printf 'scratch=%s\n' "$SCRATCH"
  } > "$evidence_dir/metadata.txt"

  set +e
  {
    printf '$ %s\n' "$command_label"
    "$@"
  } 2>&1 | tee "$evidence_dir/transcript.log"
  command_status=${PIPESTATUS[0]}
  set -e

  snapshot_links > "$evidence_dir/after-links.txt"
  if cmp -s "$evidence_dir/before-links.txt" "$evidence_dir/after-links.txt"; then
    links_unchanged=true
  else
    links_unchanged=false
  fi

  jq -n \
    --arg feature "$feature" \
    --arg host "$HOST_ATTR" \
    --arg command "$command_label" \
    --arg home_drv "$HOME_DRV" \
    --arg system_home_drv "$SYSTEM_HOME_DRV" \
    --arg profile_dir "$PROFILE_DIR" \
    --argjson exit_code "$command_status" \
    --argjson links_unchanged "$links_unchanged" \
    '{
      feature: $feature,
      host: $host,
      command: $command,
      exit_code: $exit_code,
      home_drv: $home_drv,
      system_home_drv: $system_home_drv,
      profile_dir: $profile_dir,
      shared_profile_links_unchanged: $links_unchanged
    }' > "$evidence_dir/summary.json"

  cleanup_scratch
  trap - EXIT INT TERM
  [ ! -e "$SCRATCH" ] || fail "scratch cleanup failed: $SCRATCH"
  printf 'evidence=%s\n' "$evidence_dir"

  [ "$command_status" -eq 0 ] || fail "$command_label exited with $command_status"
  [ "$links_unchanged" = "true" ] || fail "$command_label changed shared profile links"
}

usage() {
  printf 'usage: %s {doctor|home-build|darwin-build|snapshot <output-file>}\n' "$0" >&2
  exit 2
}

case "${1:-}" in
  doctor)
    [ "$#" -eq 1 ] || usage
    doctor_core
    print_doctor
    ;;
  home-build)
    [ "$#" -eq 1 ] || usage
    run_build home-partial-build "just hm-build" just hm-build
    ;;
  darwin-build)
    [ "$#" -eq 1 ] || usage
    run_build darwin-system-build "just bd" just bd
    ;;
  snapshot)
    [ "$#" -eq 2 ] || usage
    require_repo
    mkdir -p "$(dirname "$2")"
    snapshot_links > "$2"
    printf 'snapshot=%s\n' "$2"
    ;;
  *) usage ;;
esac
