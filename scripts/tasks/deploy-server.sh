#!/usr/bin/env bash

set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../.." && pwd)
config_path="$repo_root/.env.deploy"
allow_dirty_cli=0
skip_checks=0
dry_run=0
cache_root="$repo_root/.codex-cache/deploy"
archive_path=''
remote_script_path=''

usage() {
  cat <<'EOF'
Usage: ./scripts/nanoops.sh deploy [options]

Options:
  --config PATH    Use a different local deployment environment file.
  --allow-dirty    Publish uncommitted Server/Web changes.
  --skip-checks    Skip local Go and Web validation.
  --dry-run        Validate and package without connecting to the server.
  -h, --help       Show this help.
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

step() {
  printf '\n==> %s\n' "$*"
}

cleanup_local() {
  if [[ -n $archive_path ]]; then rm -f -- "$archive_path"; fi
  if [[ -n $remote_script_path ]]; then rm -f -- "$remote_script_path"; fi
}
trap cleanup_local EXIT

trim() {
  local value=$1
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required. $2"
}

load_dotenv() {
  local path=$1 raw line name value first last
  [[ -f $path ]] || die "Deployment config not found: $path. Copy .env.deploy.example to .env.deploy and edit it."

  while IFS= read -r raw || [[ -n $raw ]]; do
    raw=${raw%$'\r'}
    line=$(trim "$raw")
    [[ -z $line || ${line:0:1} == '#' ]] && continue
    [[ $line == *'='* ]] || die "Invalid .env line: $raw"
    name=$(trim "${line%%=*}")
    value=$(trim "${line#*=}")
    [[ $name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "Invalid environment variable name: $name"
    if (( ${#value} >= 2 )); then
      first=${value:0:1}
      last=${value: -1}
      if [[ ( $first == '"' && $last == '"' ) || ( $first == "'" && $last == "'" ) ]]; then
        value=${value:1:${#value}-2}
      fi
    fi
    printf -v "$name" '%s' "$value"
  done < "$path"
}

required_setting() {
  local name=$1
  local value=${!name-}
  [[ -n $value ]] || die "$name is required in $config_path"
  printf '%s' "$value"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die 'sha256sum or shasum is required.'
  fi
}

replace_placeholder() {
  local placeholder=$1 value=$2 temporary
  value=${value//\\/\\\\}
  value=${value//&/\\&}
  value=${value//|/\\|}
  temporary="$remote_script_path.tmp"
  sed "s|$placeholder|$value|g" "$remote_script_path" > "$temporary"
  mv -- "$temporary" "$remote_script_path"
}

while (( $# > 0 )); do
  case "$1" in
    --config)
      (( $# >= 2 )) || die '--config requires a path.'
      config_path=$2
      shift 2
      ;;
    --allow-dirty)
      allow_dirty_cli=1
      shift
      ;;
    --skip-checks)
      skip_checks=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

if [[ $config_path != /* ]]; then
  config_path="$repo_root/$config_path"
fi

require_command git 'Install Git.'
require_command ssh 'Install the OpenSSH client.'
require_command scp 'Install the OpenSSH client.'
require_command tar 'Install tar.'
load_dotenv "$config_path"

ssh_host=$(required_setting DEPLOY_SSH_HOST)
ssh_port=$(required_setting DEPLOY_SSH_PORT)
remote_upload_dir=$(required_setting DEPLOY_REMOTE_UPLOAD_DIR)
remote_build_root=$(required_setting DEPLOY_REMOTE_BUILD_ROOT)
compose_dir=$(required_setting DEPLOY_COMPOSE_DIR)
compose_service=$(required_setting DEPLOY_COMPOSE_SERVICE)
image_repository=$(required_setting DEPLOY_IMAGE_REPOSITORY)
health_timeout=$(required_setting DEPLOY_HEALTH_TIMEOUT_SECONDS)
host_http_port=${DEPLOY_HOST_HTTP_PORT:-8080}
local_health_url=${DEPLOY_LOCAL_HEALTH_URL:-http://127.0.0.1:${host_http_port}/api/health}
public_url=${DEPLOY_PUBLIC_URL-}
public_url=${public_url%/}
identity_file=${DEPLOY_SSH_IDENTITY_FILE-}
expected_agents=${DEPLOY_EXPECTED_AGENT_COUNT:-0}
allow_dirty_config=${DEPLOY_ALLOW_DIRTY:-false}

[[ $ssh_host =~ ^[A-Za-z0-9_.@-]+$ ]] || die 'DEPLOY_SSH_HOST contains an unsupported value.'
[[ $remote_upload_dir =~ ^/[A-Za-z0-9._/-]+$ ]] || die 'DEPLOY_REMOTE_UPLOAD_DIR must be an absolute simple path.'
[[ $remote_build_root =~ ^/[A-Za-z0-9._/-]+$ ]] || die 'DEPLOY_REMOTE_BUILD_ROOT must be an absolute simple path.'
[[ $compose_dir =~ ^/[A-Za-z0-9._/-]+$ ]] || die 'DEPLOY_COMPOSE_DIR must be an absolute simple path.'
[[ $compose_service =~ ^[A-Za-z0-9._-]+$ ]] || die 'DEPLOY_COMPOSE_SERVICE contains an unsupported value.'
[[ $image_repository =~ ^[A-Za-z0-9._/-]+$ ]] || die 'DEPLOY_IMAGE_REPOSITORY contains an unsupported value.'
[[ -z $public_url || $public_url =~ ^https://[A-Za-z0-9._:-]+$ ]] || die 'DEPLOY_PUBLIC_URL must be an HTTPS origin without a path.'
[[ $ssh_port =~ ^[0-9]+$ ]] && (( ssh_port >= 1 && ssh_port <= 65535 )) || die 'DEPLOY_SSH_PORT must be between 1 and 65535.'
[[ $health_timeout =~ ^[0-9]+$ ]] && (( health_timeout >= 30 && health_timeout <= 900 )) || die 'DEPLOY_HEALTH_TIMEOUT_SECONDS must be between 30 and 900.'
[[ $host_http_port =~ ^[0-9]+$ ]] && (( host_http_port >= 1 && host_http_port <= 65535 )) || die 'DEPLOY_HOST_HTTP_PORT must be between 1 and 65535.'
[[ $local_health_url =~ ^http://127\.0\.0\.1:([0-9]+)/api/health$ ]] || die 'DEPLOY_LOCAL_HEALTH_URL must be a loopback URL in the form http://127.0.0.1:PORT/api/health.'
local_health_port=${BASH_REMATCH[1]}
(( local_health_port >= 1 && local_health_port <= 65535 )) || die 'DEPLOY_LOCAL_HEALTH_URL contains an invalid port.'
(( local_health_port == host_http_port )) || die 'DEPLOY_LOCAL_HEALTH_URL port must match DEPLOY_HOST_HTTP_PORT.'
local_http_origin=${local_health_url%/api/health}
[[ $expected_agents =~ ^[0-9]+$ ]] || die 'DEPLOY_EXPECTED_AGENT_COUNT must be zero or greater.'
case "$allow_dirty_config" in
  true|TRUE|True) allow_dirty_config=1 ;;
  false|FALSE|False) allow_dirty_config=0 ;;
  *) die 'DEPLOY_ALLOW_DIRTY must be true or false.' ;;
esac

ssh_args=(-o BatchMode=yes -o ConnectTimeout=10 -p "$ssh_port")
scp_args=(-o BatchMode=yes -o ConnectTimeout=10 -P "$ssh_port")
if [[ -n $identity_file ]]; then
  [[ -f $identity_file ]] || die "SSH identity file does not exist: $identity_file"
  ssh_args+=(-i "$identity_file")
  scp_args+=(-i "$identity_file")
fi

cd "$repo_root"
git_args=(-c "safe.directory=$repo_root")
version=$(tr -d '\r\n' < VERSION)
[[ $version =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die 'VERSION contains an unsupported value.'
full_commit=$(git "${git_args[@]}" rev-parse HEAD)
short_commit=${full_commit:0:7}
dirty_output=$(git "${git_args[@]}" status --porcelain=v1)
is_dirty=0
if [[ -n $dirty_output ]]; then is_dirty=1; fi
if (( is_dirty && ! allow_dirty_cli && ! allow_dirty_config )); then
  printf '%s\n' "$dirty_output" >&2
  die 'The working tree is not clean. Commit the changes, use --allow-dirty, or set DEPLOY_ALLOW_DIRTY=true locally.'
fi

timestamp=$(date -u +%Y%m%d%H%M%S)
build_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if (( is_dirty )); then
  release_id="$short_commit-dirty-$timestamp"
  commit_label="$full_commit-dirty"
  image_tag="$image_repository:$version-$short_commit-dirty-$timestamp"
else
  release_id="$short_commit-$timestamp"
  commit_label=$full_commit
  image_tag="$image_repository:$version-$short_commit"
fi

printf 'Release: %s\nSource:  %s\nImage:   %s\nTarget:  %s\n' \
  "$release_id" "$commit_label" "$image_tag" "$ssh_host"

if (( ! skip_checks )); then
  require_command go 'Install Go.'
  require_command npm 'Install Node.js and npm.'
  step 'Running Go Server tests and vet'
  mkdir -p "$repo_root/.codex-cache/go-build"
  (
    cd "$repo_root/apps/server"
    GOCACHE="$repo_root/.codex-cache/go-build" go test ./...
    GOCACHE="$repo_root/.codex-cache/go-build" go vet ./...
  )

  step 'Running Web lint and production build'
  (
    cd "$repo_root/apps/server/web"
    if [[ ! -d node_modules ]]; then npm ci --no-audit --no-fund; fi
    npm run lint
    npm run build
  )
fi

step 'Creating the release archive'
mkdir -p "$cache_root"
archive_name="nanolink-$release_id.tar"
archive_path="$cache_root/$archive_name"
if (( is_dirty )); then
  tar -cf "$archive_path" \
    --exclude=apps/server/web/node_modules \
    --exclude=apps/server/web/dist \
    --exclude=apps/server/web/.vite \
    --exclude=apps/server/data \
    --exclude=apps/server/nanolink-server \
    --exclude=apps/server/nanolink.exe \
    VERSION apps/docker/Dockerfile apps/server sdk/protocol/nanolink.proto
else
  git "${git_args[@]}" archive --format=tar --output="$archive_path" HEAD \
    VERSION apps/docker/Dockerfile apps/server sdk/protocol/nanolink.proto
fi
archive_hash=$(sha256_file "$archive_path")
printf 'Archive SHA-256: %s\n' "$archive_hash"

remote_archive="$remote_upload_dir/$archive_name"
remote_script_name="deploy-$release_id.sh"
remote_script="$remote_upload_dir/$remote_script_name"
remote_build_dir="$remote_build_root/build-$release_id"
backup_file="$compose_dir/docker-compose.yml.pre-$release_id"
smoke_name="nanolink-smoke-$short_commit-$timestamp"
remote_script_path="$cache_root/$remote_script_name"

cat > "$remote_script_path" <<'REMOTE_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

archive='__ARCHIVE__'
archive_sha='__ARCHIVE_SHA__'
build_dir='__BUILD_DIR__'
compose_dir='__COMPOSE_DIR__'
compose_service='__COMPOSE_SERVICE__'
image_tag='__IMAGE_TAG__'
version='__VERSION__'
commit_label='__COMMIT_LABEL__'
build_time='__BUILD_TIME__'
backup_file='__BACKUP_FILE__'
smoke_name='__SMOKE_NAME__'
health_timeout=__HEALTH_TIMEOUT__
expected_agents=__EXPECTED_AGENTS__
public_url='__PUBLIC_URL__'
local_health_url='__LOCAL_HEALTH_URL__'
local_http_origin='__LOCAL_HTTP_ORIGIN__'
rollback_needed=0

cleanup() {
  sudo docker rm -fv "$smoke_name" >/dev/null 2>&1 || true
  rm -f "$archive" '__REMOTE_SCRIPT__'
}

on_error() {
  code=$?
  set +e
  if [[ $rollback_needed -eq 1 && -f $backup_file ]]; then
    echo "Deployment failed; restoring $backup_file" >&2
    sudo cp -a "$backup_file" "$compose_dir/docker-compose.yml"
    (cd "$compose_dir" && sudo docker compose up -d --no-deps "$compose_service")
  fi
  cleanup
  exit "$code"
}

trap on_error ERR
trap cleanup EXIT

echo "$archive_sha  $archive" | sha256sum -c -
[[ ! -e $build_dir ]]
sudo mkdir -p "$build_dir"
sudo tar -xf "$archive" -C "$build_dir"
sudo chown -R "$(id -u):$(id -g)" "$build_dir"

cd "$build_dir"
sudo docker build \
  --build-arg "VERSION=$version" \
  --build-arg "GIT_COMMIT=$commit_label" \
  --build-arg "BUILD_TIME=$build_time" \
  -t "$image_tag" \
  -f apps/docker/Dockerfile .

sudo docker run -d --name "$smoke_name" \
  -e NANOLINK_JWT_SECRET=smoke-test-only-key-at-least-32-bytes \
  "$image_tag" >/dev/null

smoke_ok=0
for ((i=0; i<30; i++)); do
  if sudo docker exec "$smoke_name" wget -qO- http://127.0.0.1:8080/api/health >/dev/null 2>&1; then
    smoke_ok=1
    break
  fi
  sleep 1
done
[[ $smoke_ok -eq 1 ]]
sudo docker exec "$smoke_name" /app/nanolink-server -version
sudo docker rm -fv "$smoke_name" >/dev/null

cd "$compose_dir"
image_lines=$(grep -Ec '^[[:space:]]+image:[[:space:]]*' docker-compose.yml)
[[ $image_lines -eq 1 ]]
sudo cp -a docker-compose.yml "$backup_file"
rollback_needed=1
sudo sed -i -E "s|^([[:space:]]*image:[[:space:]]*).*$|\1$image_tag|" docker-compose.yml
sudo docker compose config --quiet
sudo docker compose up -d --no-deps "$compose_service"

healthy=0
container_id=''
for ((i=0; i<health_timeout; i++)); do
  container_id=$(sudo docker compose ps -q "$compose_service" 2>/dev/null || true)
  status=$(sudo docker inspect "$container_id" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' 2>/dev/null || true)
  if [[ $status == healthy ]]; then
    healthy=1
    break
  fi
  sleep 1
done
[[ $healthy -eq 1 && -n $container_id ]]

health_json=$(curl -fsS "$local_health_url")
echo "Health: $health_json"
local_asset=$(curl -fsSL "$local_http_origin/dashboard" | grep -o 'assets/index-[A-Za-z0-9_-]*\.js' | head -n 1 || true)
echo "Local asset: $local_asset"

if (( expected_agents > 0 )); then
  agent_count=0
  for ((i=0; i<health_timeout; i++)); do
    health_json=$(curl -fsS "$local_health_url")
    agent_count=$(printf '%s' "$health_json" | grep -o '"agentCount":[0-9]*' | cut -d: -f2 || true)
    if (( ${agent_count:-0} >= expected_agents )); then break; fi
    sleep 1
  done
  if (( ${agent_count:-0} < expected_agents )); then
    echo "Warning: expected $expected_agents agents, currently ${agent_count:-0}" >&2
  fi
fi

if [[ -n $public_url ]]; then
  public_asset=$(curl -fsSL "$public_url/dashboard" | grep -o 'assets/index-[A-Za-z0-9_-]*\.js' | head -n 1 || true)
  echo "Public asset: $public_asset"
  if [[ -n $local_asset && $public_asset != "$local_asset" ]]; then
    echo 'Warning: public asset has not converged to the local asset yet.' >&2
  fi
fi

error_count=$(sudo docker logs --since 5m "$container_id" 2>&1 | grep -F -c 'level":"error' || true)
echo "Recent error count: $error_count"
sudo docker inspect "$container_id" --format 'Image={{.Config.Image}} Health={{.State.Health.Status}} Restarts={{.RestartCount}}'
sudo docker exec "$container_id" /app/nanolink-server -version

rollback_needed=0
trap - ERR
echo "DEPLOY_OK image=$image_tag backup=$backup_file"
REMOTE_SCRIPT

replace_placeholder __ARCHIVE__ "$remote_archive"
replace_placeholder __ARCHIVE_SHA__ "$archive_hash"
replace_placeholder __BUILD_DIR__ "$remote_build_dir"
replace_placeholder __COMPOSE_DIR__ "$compose_dir"
replace_placeholder __COMPOSE_SERVICE__ "$compose_service"
replace_placeholder __IMAGE_TAG__ "$image_tag"
replace_placeholder __VERSION__ "$version"
replace_placeholder __COMMIT_LABEL__ "$commit_label"
replace_placeholder __BUILD_TIME__ "$build_time"
replace_placeholder __BACKUP_FILE__ "$backup_file"
replace_placeholder __SMOKE_NAME__ "$smoke_name"
replace_placeholder __HEALTH_TIMEOUT__ "$health_timeout"
replace_placeholder __EXPECTED_AGENTS__ "$expected_agents"
replace_placeholder __PUBLIC_URL__ "$public_url"
replace_placeholder __LOCAL_HEALTH_URL__ "$local_health_url"
replace_placeholder __LOCAL_HTTP_ORIGIN__ "$local_http_origin"
replace_placeholder __REMOTE_SCRIPT__ "$remote_script"
chmod 700 "$remote_script_path"

if (( dry_run )); then
  printf 'Generated remote rollout script: %s\nHealth target: %s\n\nDry run completed; no remote changes were made.\n' "$remote_script_name" "$local_health_url"
  exit 0
fi

step 'Verifying passwordless SSH access'
ssh "${ssh_args[@]}" "$ssh_host" 'printf nanoops-deploy-ready'

step 'Uploading the release'
scp "${scp_args[@]}" "$archive_path" "$remote_script_path" "$ssh_host:$remote_upload_dir/"

step 'Validating the remote rollout script'
ssh "${ssh_args[@]}" "$ssh_host" "bash -n '$remote_script'"

step 'Building and rolling out on the Server'
ssh "${ssh_args[@]}" "$ssh_host" "bash '$remote_script'"

printf '\nNanoOps Server deployment completed successfully.\nImage:  %s\nSource: %s\nBackup: %s\n' \
  "$image_tag" "$commit_label" "$backup_file"
