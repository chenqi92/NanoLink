#!/usr/bin/env bash
#
# Installs the NanoOps server as a systemd service, which is the deployment
# mode that supports in-place self-update. Docker deployments upgrade by pulling
# a new image instead; see apps/docker/docker-compose.yml.
#
# Usage:
#   sudo ./install.sh                 # install the version in ./VERSION from GitHub
#   sudo ./install.sh 0.5.0           # install a specific version
#   sudo ./install.sh --local ./bin   # install a binary you already have
#
set -euo pipefail

REPO="${NANOOPS_REPO:-chenqi92/NanoLink}"
INSTALL_DIR="${NANOOPS_INSTALL_DIR:-/opt/nanoops}"
CONFIG_DIR="${NANOOPS_CONFIG_DIR:-/etc/nanoops}"
DATA_DIR="${NANOOPS_DATA_DIR:-/var/lib/nanoops}"
LOG_DIR="${NANOOPS_LOG_DIR:-/var/log/nanoops}"
SERVICE_USER="${NANOOPS_USER:-nanoops}"
SERVICE_NAME="nanoops-server"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

[ "$(id -u)" -eq 0 ] || die "must run as root (use sudo)"
command -v systemctl >/dev/null 2>&1 || die "systemd not found; this script only supports systemd hosts"

LOCAL_BINARY=""
VERSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --local) LOCAL_BINARY="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) VERSION="$1"; shift ;;
  esac
done

# Map uname output onto the release asset names.
detect_platform() {
  local os arch
  case "$(uname -s)" in
    Linux) os="linux" ;;
    Darwin) os="macos" ;;
    *) die "unsupported OS: $(uname -s)" ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
  echo "${os}-${arch}"
}

PLATFORM="$(detect_platform)"
info "Platform: $PLATFORM"

# --- account and directories -------------------------------------------------

if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  info "Creating service account: $SERVICE_USER"
  useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER"
fi

install -d -m 0755 -o "$SERVICE_USER" -g "$SERVICE_USER" "$INSTALL_DIR" "$DATA_DIR" "$LOG_DIR"
install -d -m 0750 -o root -g "$SERVICE_USER" "$CONFIG_DIR"

# --- binary ------------------------------------------------------------------

STAGED="$(mktemp)"
trap 'rm -f "$STAGED" "$STAGED.sig"' EXIT

if [ -n "$LOCAL_BINARY" ]; then
  [ -f "$LOCAL_BINARY" ] || die "no such file: $LOCAL_BINARY"
  info "Using local binary: $LOCAL_BINARY"
  cp "$LOCAL_BINARY" "$STAGED"
else
  if [ -z "$VERSION" ]; then
    if [ -f "$SCRIPT_DIR/../../../VERSION" ]; then
      VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/../../../VERSION")"
    else
      die "no version given and no VERSION file found; pass one, e.g. ./install.sh 0.5.0"
    fi
  fi
  VERSION="${VERSION#v}"
  ASSET="nanolink-server-${PLATFORM}"
  URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ASSET}"
  info "Downloading $ASSET v$VERSION"
  command -v curl >/dev/null 2>&1 || die "curl is required"
  curl -fsSL --proto '=https' --tlsv1.2 -o "$STAGED" "$URL" \
    || die "download failed: $URL"

  # Verify the signature when a public key is available. The server enforces this
  # on every self-update; doing it here means the first install is held to the
  # same standard as later ones.
  if [ -n "${NANOOPS_UPDATE_PUBLIC_KEY:-}" ]; then
    if curl -fsSL --proto '=https' --tlsv1.2 -o "$STAGED.sig" "${URL}.sig"; then
      if command -v openssl >/dev/null 2>&1 && command -v xxd >/dev/null 2>&1; then
        info "Verifying Ed25519 signature"
        KEYFILE="$(mktemp)"
        # Wrap the raw 32-byte key in the DER prefix OpenSSL expects for ed25519.
        {
          printf '302a300506032b6570032100'
          printf '%s' "$NANOOPS_UPDATE_PUBLIC_KEY"
        } | xxd -r -p > "$KEYFILE"
        SIGFILE="$(mktemp)"
        tr -d '[:space:]' < "$STAGED.sig" | xxd -r -p > "$SIGFILE"
        if openssl pkeyutl -verify -pubin -inkey "$KEYFILE" -keyform DER \
            -rawin -in "$STAGED" -sigfile "$SIGFILE" >/dev/null 2>&1; then
          info "Signature OK"
        else
          rm -f "$KEYFILE" "$SIGFILE"
          die "signature verification failed; refusing to install"
        fi
        rm -f "$KEYFILE" "$SIGFILE"
      else
        echo "warning: openssl or xxd not found, skipping signature check" >&2
      fi
    else
      echo "warning: no published signature for $ASSET" >&2
    fi
  else
    echo "warning: NANOOPS_UPDATE_PUBLIC_KEY not set, installing without signature verification" >&2
  fi
fi

chmod +x "$STAGED"
if ! "$STAGED" -version >/dev/null 2>&1; then
  die "the downloaded binary does not run on this host"
fi
info "Installing $("$STAGED" -version | head -1)"

# Keep the previous binary so a bad upgrade can be rolled back by hand.
if [ -f "$INSTALL_DIR/$SERVICE_NAME" ]; then
  cp -p "$INSTALL_DIR/$SERVICE_NAME" "$INSTALL_DIR/$SERVICE_NAME.bak"
fi
install -m 0755 -o root -g root "$STAGED" "$INSTALL_DIR/$SERVICE_NAME"

# --- config ------------------------------------------------------------------

if [ ! -f "$CONFIG_DIR/config.yaml" ]; then
  info "Writing default config to $CONFIG_DIR/config.yaml"
  cat > "$CONFIG_DIR/config.yaml" <<'YAML'
server:
  http_port: 8080
  grpc_port: 9090
  mode: release

database:
  type: sqlite
  path: /var/lib/nanoops/nanoops.db

# Self-update. source=github checks the public release feed; set source=custom
# with a custom_url when GitHub is unreachable. public_key is the Ed25519 key the
# release pipeline signs with: without it, no update can be installed.
update:
  source: github
  repo: chenqi92/NanoLink
  auto_check: true
  check_interval_hours: 24
  allow_prerelease: false
  require_signature: true
  public_key: ""
YAML
  chmod 0640 "$CONFIG_DIR/config.yaml"
  chown root:"$SERVICE_USER" "$CONFIG_DIR/config.yaml"
else
  info "Keeping existing config at $CONFIG_DIR/config.yaml"
fi

# --- service -----------------------------------------------------------------

UNIT_SRC="$SCRIPT_DIR/$SERVICE_NAME.service"
[ -f "$UNIT_SRC" ] || die "unit file not found: $UNIT_SRC"
info "Installing systemd unit"
install -m 0644 "$UNIT_SRC" "/etc/systemd/system/$SERVICE_NAME.service"
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"

if systemctl is-active --quiet "$SERVICE_NAME"; then
  info "Restarting $SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"
else
  info "Starting $SERVICE_NAME"
  systemctl start "$SERVICE_NAME"
fi

sleep 2
if systemctl is-active --quiet "$SERVICE_NAME"; then
  info "$SERVICE_NAME is running"
else
  echo "error: $SERVICE_NAME failed to start. Recent logs:" >&2
  journalctl -u "$SERVICE_NAME" -n 30 --no-pager >&2
  exit 1
fi

cat <<EOF

Installed.

  Config:  $CONFIG_DIR/config.yaml
  Data:    $DATA_DIR
  Binary:  $INSTALL_DIR/$SERVICE_NAME
  Logs:    journalctl -u $SERVICE_NAME -f

To enable self-update, set update.public_key in the config to the release
signing public key, then restart:

  sudo systemctl restart $SERVICE_NAME

EOF
