#!/usr/bin/env bash
set -Eeuo pipefail

root_dir=/data/nanoops
service_user=nanoops
service_name=nanoops-server
env_file="$root_dir/server.env"
config_file="$root_dir/config.yaml"
unit_file="$root_dir/nanoops-server.service"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '\n==> %s\n' "$*"
}

prompt_value() {
  local prompt=$1 default=$2 value
  if [[ -t 0 ]]; then
    read -r -p "$prompt [$default]: " value
    printf '%s' "${value:-$default}"
  else
    printf '%s' "$default"
  fi
}

validate_port() {
  local name=$1 value=$2
  [[ $value =~ ^[0-9]+$ ]] || die "$name must be a number"
  (( value >= 1024 && value <= 65535 )) || die "$name must be between 1024 and 65535"
}

write_env_line() {
  local name=$1 value=$2 escaped
  [[ $value != *$'\n'* && $value != *$'\r'* ]] || die "$name must not contain a newline"
  escaped=${value//\\/\\\\}
  escaped=${escaped//\"/\\\"}
  printf '%s="%s"\n' "$name" "$escaped"
}

[[ $(id -u) -eq 0 ]] || die 'run this installer as root: sudo bash install.sh'
[[ $(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) == "$root_dir" ]] || \
  die "extract the package to $root_dir before running this installer"
command -v systemctl >/dev/null 2>&1 || die 'systemd is required'
[[ -f $root_dir/nanoops-server ]] || die 'nanoops-server binary is missing'
[[ -f $config_file ]] || die 'config.yaml is missing'
[[ -f $unit_file ]] || die 'nanoops-server.service is missing'

case $(uname -m) in
  x86_64|amd64) ;;
  *) die "this package is for Linux x86_64/amd64, not $(uname -m)" ;;
esac

if ! id "$service_user" >/dev/null 2>&1; then
  info "Creating the unprivileged $service_user service account"
  nologin_shell=$(command -v nologin || true)
  useradd --system --no-create-home --shell "${nologin_shell:-/usr/sbin/nologin}" "$service_user"
fi

chown root:"$service_user" "$root_dir"
chmod 0750 "$root_dir"
install -d -m 0750 -o "$service_user" -g "$service_user" "$root_dir/data"
chmod 0750 "$root_dir/nanoops-server"
chmod 0750 "$root_dir/install.sh"
chown root:"$service_user" "$root_dir/nanoops-server" "$root_dir/install.sh" "$config_file"
chmod 0640 "$config_file"
for support_file in BUILD-INFO.txt README_CN.md SECURITY_AUDIT_CN.md SHA256SUMS \
    nanoops-server.service nginx-nanoops.conf.example server.env.example; do
  if [[ -f $root_dir/$support_file ]]; then
    chown root:"$service_user" "$root_dir/$support_file"
    chmod 0640 "$root_dir/$support_file"
  fi
done

if [[ ! -f $env_file ]]; then
  info 'Creating the root-only runtime secret file'
  http_port=$(prompt_value 'Internal HTTP port' 18080)
  ws_port=$(prompt_value 'Agent WebSocket port (keep closed until Agents are used)' 19100)
  grpc_port=$(prompt_value 'Agent gRPC port (keep closed until Agents are used)' 39100)
  validate_port NANOLINK_SERVER_HTTP_PORT "$http_port"
  validate_port NANOLINK_SERVER_WS_PORT "$ws_port"
  validate_port NANOLINK_SERVER_GRPC_PORT "$grpc_port"
  [[ $http_port != "$ws_port" && $http_port != "$grpc_port" && $ws_port != "$grpc_port" ]] || \
    die 'HTTP, WebSocket, and gRPC ports must be distinct'

  admin_username=${NANOOPS_ADMIN_USERNAME:-}
  if [[ -z $admin_username ]]; then
    admin_username=$(prompt_value 'Super administrator username' nanoops_admin)
  fi
  [[ $admin_username =~ ^[A-Za-z0-9_.-]{3,50}$ ]] || \
    die 'administrator username must be 3-50 letters, numbers, dots, underscores, or hyphens'

  admin_password=${NANOOPS_ADMIN_PASSWORD:-}
  generated_password=0
  if [[ -z $admin_password && -t 0 ]]; then
    read -r -s -p 'Super administrator password (16+ chars, letters and numbers): ' admin_password
    printf '\n'
    read -r -s -p 'Confirm password: ' password_confirmation
    printf '\n'
    [[ $admin_password == "$password_confirmation" ]] || die 'passwords do not match'
  elif [[ -z $admin_password ]]; then
    admin_password=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
    generated_password=1
  fi
  (( ${#admin_password} >= 16 )) || die 'administrator password must contain at least 16 characters'
  [[ $admin_password =~ [[:alpha:]] && $admin_password =~ [[:digit:]] ]] || \
    die 'administrator password must contain both letters and numbers'

  public_url=${NANOOPS_EXTERNAL_URL:-}
  if [[ -z $public_url && -t 0 ]]; then
    read -r -p 'Public HTTPS origin (optional, e.g. https://nanoops.example.com): ' public_url
  fi
  [[ -z $public_url || $public_url =~ ^https://[A-Za-z0-9._:-]+$ ]] || \
    die 'public URL must be an HTTPS origin without a path'

  jwt_secret=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
  tmp_env=$(mktemp "$root_dir/.server.env.XXXXXX")
  trap 'rm -f -- "${tmp_env:-}"' EXIT
  {
    write_env_line NANOLINK_SERVER_HTTP_PORT "$http_port"
    write_env_line NANOLINK_SERVER_WS_PORT "$ws_port"
    write_env_line NANOLINK_SERVER_GRPC_PORT "$grpc_port"
    write_env_line NANOLINK_JWT_EXPIRE_HOUR 12
    write_env_line NANOLINK_JWT_SECRET "$jwt_secret"
    write_env_line NANOLINK_ADMIN_USERNAME "$admin_username"
    write_env_line NANOLINK_ADMIN_PASSWORD "$admin_password"
    if [[ -n $public_url ]]; then
      write_env_line NANOLINK_EXTERNAL_URL "$public_url"
    fi
  } > "$tmp_env"
  chown root:root "$tmp_env"
  chmod 0600 "$tmp_env"
  mv -f -- "$tmp_env" "$env_file"
  trap - EXIT
  if (( generated_password )); then
    printf '\nGenerated super administrator password (store it now): %s\n' "$admin_password"
  fi
else
  info "Keeping the existing $env_file"
  chown root:root "$env_file"
  chmod 0600 "$env_file"
fi

info 'Validating the Linux binary'
"$root_dir/nanoops-server" -version

info 'Installing and starting the systemd service'
install -m 0644 -o root -g root "$unit_file" "/etc/systemd/system/$service_name.service"
systemctl daemon-reload
if command -v systemd-analyze >/dev/null 2>&1; then
  systemd-analyze verify "/etc/systemd/system/$service_name.service"
fi
systemctl enable --now "$service_name"

for _ in $(seq 1 20); do
  if systemctl is-active --quiet "$service_name"; then
    break
  fi
  sleep 1
done
if ! systemctl is-active --quiet "$service_name"; then
  journalctl -u "$service_name" -n 50 --no-pager >&2 || true
  die "$service_name failed to start"
fi

http_port=$(sed -n 's/^NANOLINK_SERVER_HTTP_PORT="\([0-9][0-9]*\)"$/\1/p' "$env_file")
printf '\nNanoOps Server is running.\n'
printf '  Health: http://127.0.0.1:%s/api/health\n' "${http_port:-18080}"
printf '  Logs:   journalctl -u %s -f\n' "$service_name"
printf '  Config: %s\n' "$config_file"
printf '  Secrets: %s (root-only)\n' "$env_file"
printf '\nDo not open the three application ports to the Internet. Use nginx + HTTPS,\n'
printf 'or an SSH tunnel, and keep Agent WebSocket/gRPC ports closed for now.\n'
