#!/usr/bin/env bash

set -euo pipefail

state_dir="${DEVENV_SHARED_PROXY_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/devenv-shared-caddy}"
runtime_root="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
runtime_dir="${DEVENV_SHARED_PROXY_RUNTIME_DIR:-$runtime_root/devenv-shared-caddy-$(id -u)}"
sites_dir="$state_dir/sites"
caddyfile="$state_dir/Caddyfile"
admin_socket="$runtime_dir/admin.sock"
pid_file="$runtime_dir/caddy.pid"
lock_dir="$state_dir/operation.lock"
lock_held=false
registrar_active=false
registration_in_progress=false
pending_exit=false
registrar_file=""

usage() {
  cat >&2 <<'EOF'
Usage: shared-proxy <command>

Commands:
  stop
  status
  doctor
  list
  registrar <project-id>
EOF
}

release_lock() {
  if [[ "$lock_held" == true ]]; then
    rm -f "$lock_dir/pid"
    rmdir "$lock_dir" 2>/dev/null || true
    lock_held=false
  fi
}

acquire_lock() {
  local attempt existing_pid
  local lock_attempts="${DEVENV_SHARED_PROXY_LOCK_ATTEMPTS:-100}"

  mkdir -p "$state_dir"
  for (( attempt = 0; attempt < lock_attempts; attempt++ )); do
    if mkdir "$lock_dir" 2>/dev/null; then
      printf '%s\n' "$$" > "$lock_dir/pid"
      lock_held=true
      return
    fi

    existing_pid=""
    if [[ -f "$lock_dir/pid" ]]; then
      read -r existing_pid < "$lock_dir/pid" || true
    fi
    if [[ ! "$existing_pid" =~ ^[0-9]+$ ]] || ! kill -0 "$existing_pid" 2>/dev/null; then
      rm -f "$lock_dir/pid"
      rmdir "$lock_dir" 2>/dev/null || true
    fi
    sleep 0.05
  done

  printf 'Timed out waiting for another shared-proxy operation to finish.\n' >&2
  return 1
}

ensure_supported_os() {
  case "$(uname -s)" in
    Darwin|Linux) ;;
    *)
      printf 'shared-proxy supports macOS and Linux only.\n' >&2
      return 1
      ;;
  esac
}

is_running() {
  local pid
  if [[ -n "${DEVENV_SHARED_PROXY_TEST_RUNNING_FILE:-}" ]]; then
    [[ -f "$DEVENV_SHARED_PROXY_TEST_RUNNING_FILE" ]]
    return
  fi
  [[ -f "$pid_file" ]] || return 1
  read -r pid < "$pid_file" || return 1
  [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

wait_until_running() {
  local attempt
  for (( attempt = 0; attempt < ${DEVENV_SHARED_PROXY_WAIT_ATTEMPTS:-100}; attempt++ )); do
    if is_running; then
      return
    fi
    sleep 0.05
  done
  printf 'Caddy did not start its private admin socket at %s.\n' "$admin_socket" >&2
  return 1
}

wait_until_stopped() {
  local attempt
  for (( attempt = 0; attempt < ${DEVENV_SHARED_PROXY_WAIT_ATTEMPTS:-100}; attempt++ )); do
    if ! is_running; then
      return
    fi
    sleep 0.05
  done
  printf 'Caddy did not stop within five seconds.\n' >&2
  return 1
}

ports_are_available() {
  local port
  for port in 80 443; do
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      printf 'TCP port %s is already in use:\n' "$port" >&2
      lsof -nP -iTCP:"$port" -sTCP:LISTEN >&2 || true
      return 1
    fi
  done
}

prepare_state() {
  mkdir -p "$state_dir/data" "$state_dir/config" "$sites_dir" "$runtime_dir"
  chmod 700 "$state_dir" "$state_dir/data" "$state_dir/config" "$sites_dir" "$runtime_dir"
  printf '%s\n' "{
  admin unix//$admin_socket
  local_certs
}

import sites/*.caddy" > "$caddyfile"
  chmod 600 "$caddyfile"
}

has_site_files() {
  [[ -n "$(find "$sites_dir" -maxdepth 1 -type f -name '*.caddy' -print -quit)" ]]
}

start_proxy_locked() {
  local caddy_bin

  if is_running; then
    return
  fi
  ensure_supported_os
  ports_are_available
  prepare_state
  rm -f "$admin_socket" "$pid_file"
  caddy_bin="$(command -v caddy)" || {
    printf 'caddy is required but was not found in PATH.\n' >&2
    return 1
  }
  if ! env \
    "XDG_DATA_HOME=$state_dir/data" \
    "XDG_CONFIG_HOME=$state_dir/config" \
    "$caddy_bin" start \
      --config "$caddyfile" \
      --adapter caddyfile \
      --pidfile "$pid_file"; then
    return 1
  fi
  chmod 600 "$admin_socket"
  wait_until_running

  "$caddy_bin" trust
}

reload_proxy_locked() {
  local caddy_bin

  caddy_bin="$(command -v caddy)" || {
    printf 'caddy is required but was not found in PATH.\n' >&2
    return 1
  }
  "$caddy_bin" reload \
    --config "$caddyfile" \
    --adapter caddyfile \
    --address "unix//$admin_socket"
}

stop_proxy_locked() {
  local caddy_bin

  if ! is_running; then
    rm -f "$admin_socket" "$pid_file"
    return
  fi
  caddy_bin="$(command -v caddy)" || return 1
  "$caddy_bin" stop --address "unix//$admin_socket"
  wait_until_stopped
  rm -f "$admin_socket" "$pid_file"
}

reconcile_proxy_locked() {
  if has_site_files; then
    if is_running; then
      reload_proxy_locked
    else
      start_proxy_locked
    fi
  else
    stop_proxy_locked
  fi
}

restore_project_file() {
  local destination="$1"
  local backup="$2"

  if [[ -f "$backup" ]]; then
    mv "$backup" "$destination"
  else
    rm -f "$destination"
  fi
}

register_project() {
  local project_id="$1"
  local project_caddyfile="$2"
  local destination temporary backup

  [[ "$project_id" =~ ^[A-Za-z0-9._-]+$ ]] || {
    printf 'Invalid project ID: %s\n' "$project_id" >&2
    return 1
  }
  [[ -n "$project_caddyfile" ]] || {
    printf 'Project Caddyfile received on standard input must not be empty.\n' >&2
    return 1
  }

  acquire_lock
  registration_in_progress=true
  prepare_state
  destination="$sites_dir/$project_id.caddy"
  registrar_file="$destination"
  backup="$(mktemp "$sites_dir/.${project_id}.backup.XXXXXX")"
  if [[ -f "$destination" ]]; then
    cp "$destination" "$backup"
  else
    rm -f "$backup"
  fi
  temporary="$(mktemp "$sites_dir/.${project_id}.XXXXXX")"
  printf '%s\n' "$project_caddyfile" > "$temporary"
  chmod 600 "$temporary"
  mv "$temporary" "$destination"

  if ! reconcile_proxy_locked; then
    restore_project_file "$destination" "$backup"
    registration_in_progress=false
    release_lock
    return 1
  fi
  rm -f "$backup"
  registrar_active=true
  registration_in_progress=false
  release_lock
  if [[ "$pending_exit" == true ]]; then
    exit 0
  fi
}

unregister_project() {
  local destination="$1"
  local backup

  acquire_lock
  if [[ ! -f "$destination" ]]; then
    release_lock
    return
  fi
  backup="$(mktemp "$sites_dir/.removed.XXXXXX")"
  mv "$destination" "$backup"
  if ! reconcile_proxy_locked; then
    mv "$backup" "$destination"
    release_lock
    return 1
  fi
  rm -f "$backup"
  release_lock
}

cleanup_on_exit() {
  if [[ "$registrar_active" == true ]]; then
    registrar_active=false
    unregister_project "$registrar_file" || true
  fi
  release_lock
}

trap cleanup_on_exit EXIT

handle_signal() {
  if [[ "$registration_in_progress" == true ]]; then
    pending_exit=true
    return
  fi
  exit 0
}

trap handle_signal INT TERM

list_sites() {
  if [[ -d "$sites_dir" ]]; then
    find "$sites_dir" -maxdepth 1 -type f -name '*.caddy' -exec basename {} .caddy \; | sort
  fi
}

run_registrar() {
  local project_id="$1"
  local project_caddyfile

  project_caddyfile="$(< /dev/stdin)"
  register_project "$project_id" "$project_caddyfile"
  printf 'Registered shared-proxy Caddyfile for project %s.\n' "$project_id"
  while sleep 1; do :; done
}

show_status() {
  if is_running; then
    printf 'Shared Caddy proxy is running.\n'
    list_sites
    return
  fi
  printf 'Shared Caddy proxy is stopped.\n'
  return 1
}

run_doctor() {
  local dependency failed=false
  printf 'Platform: %s\n' "$(uname -s)"
  ensure_supported_os || failed=true
  for dependency in caddy lsof; do
    if command -v "$dependency" >/dev/null 2>&1; then
      printf '%s: found\n' "$dependency"
    else
      printf '%s: missing\n' "$dependency"
      failed=true
    fi
  done
  printf 'State directory: %s\n' "$state_dir"
  printf 'Runtime directory: %s\n' "$runtime_dir"
  [[ "$failed" == false ]]
}

command="${1:-}"
case "$command" in
  stop)
    [[ $# -eq 1 ]] || { usage; exit 2; }
    acquire_lock
    stop_proxy_locked
    release_lock
    ;;
  status)
    [[ $# -eq 1 ]] || { usage; exit 2; }
    show_status
    ;;
  doctor)
    [[ $# -eq 1 ]] || { usage; exit 2; }
    run_doctor
    ;;
  list)
    [[ $# -eq 1 ]] || { usage; exit 2; }
    list_sites
    ;;
  registrar)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    run_registrar "$2"
    ;;
  *)
    usage
    exit 2
    ;;
esac
