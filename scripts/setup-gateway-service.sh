#!/usr/bin/env bash
# Hermes Gateway — Systemd Service Setup
# Installs the hermes gateway as a systemd service so it runs on boot
# without needing an open terminal.
#
# Usage:
#   bash scripts/setup-gateway-service.sh              # interactive
#   bash scripts/setup-gateway-service.sh --profile soci --user root --force
#
# Flags:
#   --profile NAME    Hermes profile to use (default: soci)
#   --user USER       Run service as this user (default: current user)
#   --force           Overwrite existing service
#   --uninstall       Remove the service instead

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${GREEN}[INFO]${RESET} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $1"; }
err()     { echo -e "${RED}[ERR]${RESET}  $1"; }
bold()    { echo -e "${BOLD}$1${RESET}"; }

# ── Parse args ──────────────────────────────────────────────────────────────
PROFILE="soci"
RUN_AS_USER="$(whoami)"
FORCE=false
UNINSTALL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --user)    RUN_AS_USER="$2"; shift 2 ;;
    --force)   FORCE=true; shift ;;
    --uninstall) UNINSTALL=true; shift ;;
    -h|--help)
      echo "Usage: $0 [--profile NAME] [--user USER] [--force] [--uninstall]"
      exit 0 ;;
    *) err "Unknown flag: $1"; exit 1 ;;
  esac
done

SERVICE_NAME="hermes-gateway-${PROFILE}"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# ── Uninstall ───────────────────────────────────────────────────────────────
if $UNINSTALL; then
  bold "Removing ${SERVICE_NAME}…"
  systemctl stop "$SERVICE_NAME" 2>/dev/null || true
  systemctl disable "$SERVICE_NAME" 2>/dev/null || true
  rm -f "$SERVICE_FILE"
  systemctl daemon-reload
  info "Service ${SERVICE_NAME} removed"
  exit 0
fi

# ── Preflight ───────────────────────────────────────────────────────────────
bold "Setting up gateway service: ${SERVICE_NAME}"

# Find hermes binary
HERMES_BIN=$(command -v hermes 2>/dev/null || echo "")
if [[ -z "$HERMES_BIN" ]]; then
  # Try common locations
  for candidate in /root/.local/bin/hermes /usr/local/bin/hermes ~/.local/bin/hermes; do
    if [[ -x "$candidate" ]]; then
      HERMES_BIN="$candidate"
      break
    fi
  done
fi
if [[ -z "$HERMES_BIN" ]]; then
  err "hermes binary not found. Install hermes first."
  exit 1
fi
info "hermes: $HERMES_BIN"

# Resolve profile directory
if [[ "$PROFILE" == "default" || -z "$PROFILE" ]]; then
  HERMES_HOME="${HOME}/.hermes"
else
  # Check if running as root, use /root/.hermes, otherwise ~/
  if [[ "$(whoami)" == "root" && "$RUN_AS_USER" == "root" ]]; then
    HERMES_HOME="/root/.hermes/profiles/${PROFILE}"
  else
    eval_home=$(eval echo "~${RUN_AS_USER}")
    HERMES_HOME="${eval_home}/.hermes/profiles/${PROFILE}"
  fi
fi

if [[ ! -d "$HERMES_HOME" ]]; then
  err "Profile directory not found: $HERMES_HOME"
  err "Create it first with: hermes profile create ${PROFILE}"
  exit 1
fi
info "HERMES_HOME: $HERMES_HOME"

# Find hermes-agent project root (where venv lives)
# Try common locations relative to hermes binary
HERMES_AGENT_DIR=""
HERMES_BIN_REAL=$(readlink -f "$HERMES_BIN")
BIN_VENV_DIR=$(dirname "$(dirname "$HERMES_BIN_REAL")")

if [[ -f "${BIN_VENV_DIR}/bin/python" && -d "${BIN_VENV_DIR}/../hermes_cli" ]]; then
  HERMES_AGENT_DIR=$(dirname "$BIN_VENV_DIR")
elif [[ -d "/root/.hermes/hermes-agent" ]]; then
  HERMES_AGENT_DIR="/root/.hermes/hermes-agent"
fi

if [[ -z "$HERMES_AGENT_DIR" || ! -d "$HERMES_AGENT_DIR" ]]; then
  err "Cannot find hermes-agent project directory"
  err "Set it manually in the service file"
  exit 1
fi
info "hermes-agent: $HERMES_AGENT_DIR"

# Find Python in venv
PYTHON_PATH="${HERMES_AGENT_DIR}/venv/bin/python"
if [[ ! -x "$PYTHON_PATH" ]]; then
  PYTHON_PATH="${HERMES_AGENT_DIR}/.venv/bin/python"
fi
if [[ ! -x "$PYTHON_PATH" ]]; then
  PYTHON_PATH=$(command -v python3)
fi
if [[ -z "$PYTHON_PATH" ]]; then
  err "Cannot find Python"
  exit 1
fi
info "Python: $PYTHON_PATH"

# Check if service already exists
if [[ -f "$SERVICE_FILE" && "$FORCE" == false ]]; then
  warn "Service already exists: $SERVICE_FILE"
  echo "  Use --force to overwrite"
  echo "  Or manage it with:"
  echo "    sudo systemctl status ${SERVICE_NAME}"
  echo "    sudo systemctl restart ${SERVICE_NAME}"
  exit 0
fi

# Validate: can target user access the paths?
if [[ "$RUN_AS_USER" != "root" ]]; then
  INACCESSIBLE=()
  sudo -u "$RUN_AS_USER" test -r "$HERMES_AGENT_DIR" || INACCESSIBLE+=("WorkingDirectory: $HERMES_AGENT_DIR")
  sudo -u "$RUN_AS_USER" test -x "$PYTHON_PATH" || INACCESSIBLE+=("Python: $PYTHON_PATH")
  sudo -u "$RUN_AS_USER" test -r "$HERMES_HOME" || INACCESSIBLE+=("HERMES_HOME: $HERMES_HOME")

  if [[ ${#INACCESSIBLE[@]} -gt 0 ]]; then
    err "User '${RUN_AS_USER}' cannot access required paths:"
    for p in "${INACCESSIBLE[@]}"; do
      echo "  $p"
    done
    echo ""
    warn "Fix options:"
    echo "  1. Install hermes under ${RUN_AS_USER}'s home directory"
    echo "  2. Run as root: $0 --profile ${PROFILE} --user root"
    exit 1
  fi
fi

# ── Generate service file ───────────────────────────────────────────────────
bold "Generating ${SERVICE_FILE}…"

# Build PATH
USER_HOME=$(eval echo "~${RUN_AS_USER}" 2>/dev/null || echo "/root")
PATH_ENTRIES="${HERMES_AGENT_DIR}/venv/bin:${HERMES_AGENT_DIR}/.venv/bin:${HERMES_AGENT_DIR}/node_modules/.bin:${USER_HOME}/.local/bin:${USER_HOME}/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Profile arg
PROFILE_ARG=""
if [[ -n "$PROFILE" && "$PROFILE" != "default" ]]; then
  PROFILE_ARG="--profile ${PROFILE}"
fi

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Hermes Gateway - ${PROFILE}
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=600
StartLimitBurst=5

[Service]
Type=simple
User=${RUN_AS_USER}
Group=${RUN_AS_USER}
ExecStart=${PYTHON_PATH} -m hermes_cli.main ${PROFILE_ARG} gateway run --replace
WorkingDirectory=${HERMES_AGENT_DIR}
Environment="HOME=${USER_HOME}"
Environment="USER=${RUN_AS_USER}"
Environment="LOGNAME=${RUN_AS_USER}"
Environment="PATH=${PATH_ENTRIES}"
Environment="VIRTUAL_ENV=${HERMES_AGENT_DIR}/venv"
Environment="HERMES_HOME=${HERMES_HOME}"
Restart=on-failure
RestartSec=30
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=60
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

info "Service file written"

# ── Enable & start ──────────────────────────────────────────────────────────
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

sleep 2

STATUS=$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || echo "unknown")
if [[ "$STATUS" == "active" ]]; then
  info "Service ${SERVICE_NAME} is running ✓"
else
  warn "Service status: $STATUS"
  echo "  Check logs: journalctl -u ${SERVICE_NAME} -f"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
bold "Gateway service ready!"
echo ""
echo "  Service:  ${SERVICE_NAME}"
echo "  Profile:  ${PROFILE}"
echo "  User:     ${RUN_AS_USER}"
echo "  Status:   systemctl status ${SERVICE_NAME}"
echo "  Logs:     journalctl -u ${SERVICE_NAME} -f"
echo "  Restart:  sudo systemctl restart ${SERVICE_NAME}"
echo "  Remove:   $0 --profile ${PROFILE} --uninstall"
echo ""
