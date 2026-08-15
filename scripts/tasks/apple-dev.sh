#!/usr/bin/env bash

set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../.." && pwd)

project_path="${PROJECT_PATH:-$repo_root/apps/ios/NanoLink.xcodeproj}"
ios_scheme="${IOS_SCHEME:-NanoLink}"
mac_scheme="${MAC_SCHEME:-NanoLink}"
ios_configuration="${IOS_CONFIGURATION:-Debug}"
mac_configuration="${MAC_CONFIGURATION:-Debug}"
development_team="${DEVELOPMENT_TEAM:-2U97K3U27A}"
bundle_id_override="${BUNDLE_ID:-}"
device_timeout="${DEVICE_TIMEOUT:-120}"
device_discovery_timeout="${DEVICE_DISCOVERY_TIMEOUT:-15}"
ios_signing_mode="${IOS_SIGNING_MODE:-manual}"
ios_provisioning_profile="${IOS_PROVISIONING_PROFILE:-}"
ios_signing_identity="${IOS_SIGNING_IDENTITY:-}"
mac_signing_mode="${MAC_SIGNING_MODE:-adhoc}"

ios_derived_data="${IOS_DERIVED_DATA:-$repo_root/apps/ios/build/DeveloperWorkflow/iOS}"
mac_derived_data="${MAC_DERIVED_DATA:-$repo_root/apps/ios/build/DeveloperWorkflow/macOS}"
ios_app_path="${IOS_APP_PATH:-$ios_derived_data/Build/Products/$ios_configuration-iphoneos/NanoLink.app}"
mac_app_path="${MAC_APP_PATH:-$mac_derived_data/Build/Products/$mac_configuration-maccatalyst/NanoLink.app}"

device_temp_dir=""
device_json=""
device_core_id=""
device_udid=""
device_name=""
device_model=""
device_os=""
built_bundle_id=""
signing_temp_dir=""
profile_plist=""
signing_entitlements=""

usage() {
  cat <<'EOF'
用法：
  ./scripts/nanoops.sh install
  ./scripts/nanoops.sh ios-overwrite
  ./scripts/nanoops.sh ios-clean
  ./scripts/nanoops.sh devices
  ./scripts/nanoops.sh mac
  ./scripts/nanoops.sh mac-build

操作：
  install           选择 iPhone/iPad，再交互选择覆盖安装或完全重装
  ios-overwrite     编译并覆盖安装，保留 App 本地数据
  ios-clean         编译后卸载并重新安装，会清除 App 本地数据
  devices           检查当前可用于开发的物理 iPhone/iPad
  mac               编译并启动 Mac Catalyst App
  mac-build         只编译 Mac Catalyst App，不启动

兼容别名：iphone-overwrite、iphone-clean

常用环境变量：
  DEVICE_ID                 设备名、CoreDevice ID 或硬件 UDID
  DEVELOPMENT_TEAM          iOS 开发团队，默认 2U97K3U27A
  BUNDLE_ID                 可选 Bundle ID 覆盖；默认读取工程设置
  IOS_CONFIGURATION         iOS 构建配置，默认 Debug
  MAC_CONFIGURATION         macOS 构建配置，默认 Debug
  IOS_DERIVED_DATA          iOS DerivedData 路径
  MAC_DERIVED_DATA          macOS DerivedData 路径
  DEVICE_TIMEOUT            devicectl 操作超时秒数，默认 120
  DEVICE_DISCOVERY_TIMEOUT  设备发现单次超时秒数，默认 15
  IOS_SIGNING_MODE          manual 或 automatic，默认 manual
  IOS_PROVISIONING_PROFILE  manual 模式使用的 .mobileprovision 路径
  IOS_SIGNING_IDENTITY      manual 模式使用的证书名称或 SHA-1；默认从描述文件匹配
  MAC_SIGNING_MODE          adhoc 或 automatic，默认 adhoc
EOF
}

require_command() {
  local command_name=$1
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "缺少命令：$command_name" >&2
    exit 1
  fi
}

ensure_macos() {
  if [[ $(uname -s) != Darwin ]]; then
    echo "Apple App 构建和设备安装只能在安装了 Xcode 的 macOS 上运行。" >&2
    exit 1
  fi
}

ensure_project_exists() {
  if [[ ! -d $project_path ]]; then
    echo "找不到 Xcode 工程：$project_path" >&2
    exit 1
  fi
}

cleanup_device_temp() {
  if [[ -z $device_temp_dir || ! -d $device_temp_dir ]]; then
    return
  fi
  if [[ -f $device_json ]]; then
    rm -f "$device_json"
  fi
  rmdir "$device_temp_dir" 2>/dev/null || true
  device_temp_dir=""
  device_json=""
}

cleanup_signing_temp() {
  if [[ -z $signing_temp_dir || ! -d $signing_temp_dir ]]; then
    return
  fi
  rm -f "$signing_temp_dir"/*
  rmdir "$signing_temp_dir" 2>/dev/null || true
  signing_temp_dir=""
  profile_plist=""
  signing_entitlements=""
}

cleanup_temp() {
  cleanup_device_temp
  cleanup_signing_temp
}

trap cleanup_temp EXIT

plist_value() {
  /usr/bin/plutil -extract "$1" raw "$device_json" 2>/dev/null || true
}

fetch_device_details() {
  local requested_id=$1
  local attempt=1

  while (( attempt <= 3 )); do
    rm -f "$device_json"
    if xcrun devicectl device info details \
      --device "$requested_id" \
      --quiet \
      --timeout "$device_discovery_timeout" \
      --json-output "$device_json"; then
      return 0
    fi

    if (( attempt < 3 )); then
      echo "设备详情暂不可用，正在重试（$((attempt + 1))/3）……"
      sleep 1
    fi
    attempt=$((attempt + 1))
  done

  return 1
}

load_ios_devices() {
  ios_device_names=()
  ios_device_models=()
  ios_device_oses=()
  ios_device_transports=()
  ios_device_core_ids=()
  ios_device_udids=()
  ios_device_ready=()
  ios_device_reasons=()

  echo "正在读取 iPhone/iPad 设备列表……"
  local candidate_ids=()
  if [[ -n ${DEVICE_ID:-} ]]; then
    candidate_ids+=("$DEVICE_ID")
  else
    local xctrace_output
    if ! xctrace_output=$(xcrun xctrace list devices 2>/dev/null); then
      echo "无法读取 Xcode 设备列表。请检查 Xcode 命令行工具和设备连接。" >&2
      exit 1
    fi

    local in_device_section=false
    local line
    local udid_pattern='[(]([0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}|[0-9A-Fa-f]{40})[)][[:space:]]*$'
    while IFS= read -r line; do
      if [[ $line == "== Devices ==" || $line == "== Devices Offline ==" ]]; then
        in_device_section=true
        continue
      fi
      if [[ $line == "== Simulators ==" ]]; then
        break
      fi
      if [[ $line == "=="* ]]; then
        in_device_section=false
        continue
      fi
      if [[ $in_device_section == true && $line =~ $udid_pattern ]]; then
        candidate_ids+=("${BASH_REMATCH[1]}")
      fi
    done <<< "$xctrace_output"
  fi

  if (( ${#candidate_ids[@]} == 0 )); then
    return
  fi

  device_temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/nanoops-apple-devices.XXXXXX")
  device_json="$device_temp_dir/device.json"

  local index platform reality name model os_version core_id udid
  local pairing_state tunnel_state transport_type developer_mode ddi_available
  local ready reason

  for ((index = 0; index < ${#candidate_ids[@]}; index++)); do
    if ! fetch_device_details "${candidate_ids[$index]}"; then
      if [[ -n ${DEVICE_ID:-} ]]; then
        echo "无法读取目标设备详情：$DEVICE_ID" >&2
        exit 1
      fi
      echo "跳过无法读取详情的设备：${candidate_ids[$index]}" >&2
      continue
    fi

    platform=$(plist_value result.hardwareProperties.platform)
    reality=$(plist_value result.hardwareProperties.reality)
    if [[ $platform != iOS || $reality != physical ]]; then
      continue
    fi

    name=$(plist_value result.deviceProperties.name)
    model=$(plist_value result.hardwareProperties.marketingName)
    os_version=$(plist_value result.deviceProperties.osVersionNumber)
    core_id=$(plist_value result.identifier)
    udid=$(plist_value result.hardwareProperties.udid)
    pairing_state=$(plist_value result.connectionProperties.pairingState)
    tunnel_state=$(plist_value result.connectionProperties.tunnelState)
    transport_type=$(plist_value result.connectionProperties.transportType)
    developer_mode=$(plist_value result.deviceProperties.developerModeStatus)
    ddi_available=$(plist_value result.deviceProperties.ddiServicesAvailable)

    ready=false
    reason=""
    if [[ $pairing_state != paired ]]; then
      reason="未配对"
    elif [[ $tunnel_state != connected ]]; then
      reason="未连接"
    elif [[ $developer_mode != enabled ]]; then
      reason="Developer Mode 未启用"
    elif [[ $ddi_available != true ]]; then
      reason="开发服务未就绪"
    elif [[ -z $core_id || -z $udid ]]; then
      reason="缺少设备标识"
    else
      ready=true
    fi

    ios_device_names+=("$name")
    ios_device_models+=("$model")
    ios_device_oses+=("$os_version")
    ios_device_transports+=("$transport_type")
    ios_device_core_ids+=("$core_id")
    ios_device_udids+=("$udid")
    ios_device_ready+=("$ready")
    ios_device_reasons+=("$reason")
  done

  cleanup_device_temp
}

print_ios_device() {
  local index=$1
  local transport=${ios_device_transports[$index]}
  case "$transport" in
    wired) transport=USB ;;
    localNetwork) transport=Wi-Fi ;;
    "") transport=未知连接 ;;
  esac

  printf '%s — %s — iOS/iPadOS %s — %s — %s' \
    "${ios_device_names[$index]}" \
    "${ios_device_models[$index]}" \
    "${ios_device_oses[$index]}" \
    "$transport" \
    "${ios_device_udids[$index]}"
}

select_ios_device_at_index() {
  local index=$1
  device_name=${ios_device_names[$index]}
  device_model=${ios_device_models[$index]}
  device_os=${ios_device_oses[$index]}
  device_core_id=${ios_device_core_ids[$index]}
  device_udid=${ios_device_udids[$index]}

  echo "目标设备：$device_name — $device_model — iOS/iPadOS $device_os"
  echo "Xcode 构建 UDID：$device_udid"
}

show_ios_devices() {
  load_ios_devices

  if (( ${#ios_device_names[@]} == 0 )); then
    echo "没有发现当前在线的物理 iPhone 或 iPad。" >&2
    return 1
  fi

  echo
  echo "已发现的 iPhone/iPad："
  local index
  for ((index = 0; index < ${#ios_device_names[@]}; index++)); do
    printf '%s' '- '
    print_ios_device "$index"
    if [[ ${ios_device_ready[$index]} == true ]]; then
      echo "（可用）"
    else
      printf '（不可用：%s）\n' "${ios_device_reasons[$index]}"
    fi
  done
}

select_ios_device() {
  load_ios_devices

  if (( ${#ios_device_names[@]} == 0 )); then
    echo "没有发现物理 iPhone 或 iPad。请连接并解锁设备后重试。" >&2
    exit 1
  fi

  local index match_index=-1 match_count=0
  if [[ -n ${DEVICE_ID:-} ]]; then
    for ((index = 0; index < ${#ios_device_names[@]}; index++)); do
      if [[ $DEVICE_ID == "${ios_device_names[$index]}" || \
            $DEVICE_ID == "${ios_device_core_ids[$index]}" || \
            $DEVICE_ID == "${ios_device_udids[$index]}" ]]; then
        match_index=$index
        match_count=$((match_count + 1))
      fi
    done

    if (( match_count == 0 )); then
      echo "找不到 DEVICE_ID 指定的 iPhone/iPad：$DEVICE_ID" >&2
      exit 1
    fi
    if (( match_count > 1 )); then
      echo "DEVICE_ID 匹配到多个设备，请改用 CoreDevice ID 或硬件 UDID。" >&2
      exit 1
    fi
    if [[ ${ios_device_ready[$match_index]} != true ]]; then
      echo "目标设备当前不可用：${ios_device_reasons[$match_index]}。" >&2
      echo "请解锁、信任此 Mac，并等待 Xcode 完成设备准备。" >&2
      exit 1
    fi

    select_ios_device_at_index "$match_index"
    return
  fi

  local ready_indices=()
  for ((index = 0; index < ${#ios_device_names[@]}; index++)); do
    if [[ ${ios_device_ready[$index]} == true ]]; then
      ready_indices+=("$index")
    fi
  done

  if (( ${#ready_indices[@]} == 0 )); then
    echo "没有已连接且可用于开发的 iPhone/iPad。" >&2
    for ((index = 0; index < ${#ios_device_names[@]}; index++)); do
      printf '%s' '- ' >&2
      print_ios_device "$index" >&2
      printf '（%s）\n' "${ios_device_reasons[$index]}" >&2
    done
    exit 1
  fi

  if (( ${#ready_indices[@]} == 1 )); then
    select_ios_device_at_index "${ready_indices[0]}"
    return
  fi

  echo
  echo "可用的 iPhone/iPad："
  local selection_number
  for ((index = 0; index < ${#ready_indices[@]}; index++)); do
    selection_number=$((index + 1))
    printf '%d) ' "$selection_number"
    print_ios_device "${ready_indices[$index]}"
    echo
  done

  local selection selected_index=-1 selection_match_count candidate_index
  while (( selected_index < 0 )); do
    echo
    printf '请选择目标设备（输入序号、设备名或 UDID，q 退出）：'
    if ! IFS= read -r selection; then
      echo
      echo "未选择设备，操作已取消。" >&2
      exit 1
    fi

    if [[ $selection == q || $selection == Q ]]; then
      echo "操作已取消。"
      exit 0
    fi

    if [[ $selection =~ ^[0-9]+$ ]]; then
      if (( selection >= 1 && selection <= ${#ready_indices[@]} )); then
        selected_index=${ready_indices[$((selection - 1))]}
      fi
    else
      selection_match_count=0
      for ((index = 0; index < ${#ready_indices[@]}; index++)); do
        candidate_index=${ready_indices[$index]}
        if [[ $selection == "${ios_device_names[$candidate_index]}" || \
              $selection == "${ios_device_core_ids[$candidate_index]}" || \
              $selection == "${ios_device_udids[$candidate_index]}" ]]; then
          selected_index=$candidate_index
          selection_match_count=$((selection_match_count + 1))
        fi
      done
      if (( selection_match_count > 1 )); then
        selected_index=-1
        echo "设备名匹配到多台设备，请改用序号或 UDID。" >&2
        continue
      fi
    fi

    if (( selected_index < 0 )); then
      echo "无法识别设备：${selection}。请输入列表序号、设备名或 UDID。" >&2
    fi
  done

  select_ios_device_at_index "$selected_index"
}

resolve_built_bundle_id() {
  built_bundle_id=$(/usr/bin/plutil -extract CFBundleIdentifier raw "$ios_app_path/Info.plist" 2>/dev/null || true)
  if [[ -z $built_bundle_id ]]; then
    echo "无法从已构建 App 读取 Bundle ID：${ios_app_path}" >&2
    exit 1
  fi
}

decode_profile() {
  local profile=$1
  security cms -D -i "$profile" -o "$profile_plist" >/dev/null
}

profile_matches_target() {
  local profile=$1
  if ! decode_profile "$profile"; then
    return 1
  fi

  local team app_identifier profile_bundle provisioned_devices get_task_allow expiration now
  team=$(/usr/bin/plutil -extract TeamIdentifier.0 raw "$profile_plist" 2>/dev/null || true)
  app_identifier=$(/usr/bin/plutil -extract Entitlements.application-identifier raw "$profile_plist" 2>/dev/null || true)
  provisioned_devices=$(/usr/bin/plutil -extract ProvisionedDevices json -o - "$profile_plist" 2>/dev/null || true)
  get_task_allow=$(/usr/bin/plutil -extract Entitlements.get-task-allow raw "$profile_plist" 2>/dev/null || true)
  expiration=$(/usr/bin/plutil -extract ExpirationDate raw "$profile_plist" 2>/dev/null || true)
  now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  profile_bundle=${app_identifier#*.}

  [[ -n $team && $team == "$development_team" ]] || return 1
  [[ $get_task_allow == true ]] || return 1
  [[ -n $expiration && $expiration > $now ]] || return 1
  [[ $provisioned_devices == *"\"$device_udid\""* ]] || return 1
  [[ $profile_bundle == '*' || $profile_bundle == "$built_bundle_id" ]] || return 1
}

select_provisioning_profile() {
  signing_temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/nanoops-ios-signing.XXXXXX")
  profile_plist="$signing_temp_dir/profile.plist"
  signing_entitlements="$signing_temp_dir/entitlements.plist"

  if [[ -n $ios_provisioning_profile ]]; then
    if [[ ! -f $ios_provisioning_profile ]]; then
      echo "找不到描述文件：$ios_provisioning_profile" >&2
      exit 1
    fi
    if ! profile_matches_target "$ios_provisioning_profile"; then
      echo "描述文件与团队、Bundle ID 或目标设备不匹配：$ios_provisioning_profile" >&2
      exit 1
    fi
    return
  fi

  local profile_dir="${HOME:?}/Library/Developer/Xcode/UserData/Provisioning Profiles"
  local profile
  for profile in "$profile_dir"/*.mobileprovision; do
    [[ -f $profile ]] || continue
    if profile_matches_target "$profile"; then
      ios_provisioning_profile=$profile
      return
    fi
  done

  echo "没有找到同时匹配团队 ${development_team}、${built_bundle_id} 和目标设备的开发描述文件。" >&2
  echo "可通过 IOS_PROVISIONING_PROFILE 显式指定描述文件。" >&2
  exit 1
}

select_signing_identity() {
  if [[ -n $ios_signing_identity ]]; then
    return
  fi

  local identities encoded_certificate decoded_certificate fingerprint_line fingerprint index=0
  identities=$(security find-identity -v -p codesigning)
  encoded_certificate="$signing_temp_dir/certificate.b64"
  decoded_certificate="$signing_temp_dir/certificate.der"

  while /usr/bin/plutil -extract "DeveloperCertificates.$index" raw \
    -o "$encoded_certificate" "$profile_plist" 2>/dev/null; do
    base64 -D -i "$encoded_certificate" -o "$decoded_certificate"
    fingerprint_line=$(openssl x509 -inform DER -in "$decoded_certificate" -noout -fingerprint -sha1)
    fingerprint=${fingerprint_line#*=}
    fingerprint=${fingerprint//:/}
    if [[ $identities == *"$fingerprint"* ]]; then
      ios_signing_identity=$fingerprint
      return
    fi
    index=$((index + 1))
  done

  echo "描述文件包含的开发证书未安装在当前钥匙串。" >&2
  echo "可通过 IOS_SIGNING_IDENTITY 显式指定签名证书。" >&2
  exit 1
}

prepare_signing_entitlements() {
  local app_identifier="$development_team.$built_bundle_id"
  /usr/bin/plutil -extract Entitlements xml1 -o "$signing_entitlements" "$profile_plist"
  /usr/bin/plutil -replace application-identifier -string "$app_identifier" "$signing_entitlements"
  /usr/bin/plutil -replace 'com\.apple\.developer\.team-identifier' \
    -string "$development_team" "$signing_entitlements"
  /usr/bin/plutil -replace keychain-access-groups \
    -json "[\"$app_identifier\"]" "$signing_entitlements"
}

sign_ios_app() {
  select_provisioning_profile
  select_signing_identity
  prepare_signing_entitlements

  echo "正在使用离线描述文件签名（${development_team}）……"
  cp "$ios_provisioning_profile" "$ios_app_path/embedded.mobileprovision"

  local nested_code
  while IFS= read -r nested_code; do
    codesign --force --sign "$ios_signing_identity" --timestamp=none "$nested_code"
  done < <(find "$ios_app_path" -type f -name '*.dylib' -print)
  while IFS= read -r nested_code; do
    codesign --force --sign "$ios_signing_identity" --timestamp=none "$nested_code"
  done < <(find "$ios_app_path" -depth -type d \( -name '*.framework' -o -name '*.appex' -o -name '*.xpc' \) -print)

  codesign --force --sign "$ios_signing_identity" --timestamp=none \
    --entitlements "$signing_entitlements" \
    --generate-entitlement-der \
    "$ios_app_path"
  codesign --verify --deep --strict --verbose=2 "$ios_app_path"
  echo "离线签名完成：$ios_provisioning_profile"
}

build_ios() {
  echo
  echo "正在为 ${device_name} 编译 App（${ios_configuration}）……"
  local build_command=(
    xcodebuild
    -project "$project_path"
    -scheme "$ios_scheme"
    -configuration "$ios_configuration"
    -destination "id=$device_udid"
    -derivedDataPath "$ios_derived_data"
  )
  if [[ -n $bundle_id_override ]]; then
    build_command+=("PRODUCT_BUNDLE_IDENTIFIER=$bundle_id_override")
  fi

  case "$ios_signing_mode" in
    manual)
      build_command+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
      ;;
    automatic)
      build_command+=(-allowProvisioningUpdates)
      if [[ -n $development_team ]]; then
        build_command+=("DEVELOPMENT_TEAM=$development_team")
      fi
      ;;
    *)
      echo "IOS_SIGNING_MODE 仅支持 manual 或 automatic：$ios_signing_mode" >&2
      exit 1
      ;;
  esac
  "${build_command[@]}" build

  if [[ ! -d $ios_app_path ]]; then
    echo "编译完成，但找不到 App：$ios_app_path" >&2
    exit 1
  fi
  resolve_built_bundle_id
  if [[ $ios_signing_mode == manual ]]; then
    sign_ios_app
  fi
  echo "已构建：${ios_app_path}（${built_bundle_id}）"
}

install_ios() {
  echo
  echo "正在安装到 ${device_name}……"
  xcrun devicectl device install app \
    --device "$device_core_id" \
    --timeout "$device_timeout" \
    "$ios_app_path"
}

launch_ios() {
  echo
  echo "正在启动 ${device_name} 上的 App……"
  if xcrun devicectl device process launch \
    --device "$device_core_id" \
    --timeout "$device_timeout" \
    --terminate-existing \
    "$built_bundle_id"; then
    echo "${device_name} 上的 App 已安装并启动。"
    return
  fi

  echo "App 已安装，但自动启动失败。请解锁 ${device_name} 后手动启动，或重新运行此操作。" >&2
  return 1
}

ensure_ios_device_selected() {
  if [[ -z $device_core_id || -z $device_udid ]]; then
    select_ios_device
  fi
}

ios_clean_install() {
  ensure_ios_device_selected
  build_ios

  echo
  echo "警告：下一步会卸载 ${built_bundle_id}，并删除它在 ${device_name} 上的全部本地数据。"
  printf '输入 DELETE 继续完全重装：'
  local confirmation
  if ! IFS= read -r confirmation; then
    echo
    echo "未确认删除，操作已取消；现有 App 和数据未变更。"
    return
  fi
  if [[ $confirmation != DELETE ]]; then
    echo "未确认删除，操作已取消；现有 App 和数据未变更。"
    return
  fi

  echo
  echo "正在卸载旧 App 和本地数据……"
  if ! xcrun devicectl device uninstall app \
    --device "$device_core_id" \
    --timeout "$device_timeout" \
    "$built_bundle_id"; then
    echo "卸载失败，已停止安装，避免把覆盖安装误当成完全重装。" >&2
    return 1
  fi

  install_ios
  launch_ios
}

ios_overwrite_install() {
  ensure_ios_device_selected
  build_ios
  install_ios
  launch_ios
}

interactive_ios_install() {
  select_ios_device

  while true; do
    echo
    echo "请选择安装方式："
    echo "1) 覆盖安装（保留 App 本地数据）"
    echo "2) 完全重装（清除 App 本地数据）"
    echo "q) 取消"
    echo
    printf '请选择：'

    local install_selection
    if ! IFS= read -r install_selection; then
      echo
      echo "未选择安装方式，操作已取消。"
      return
    fi

    case "$install_selection" in
      1) ios_overwrite_install; return ;;
      2) ios_clean_install; return ;;
      q|Q) echo "操作已取消。"; return ;;
      *) echo "无效选项：$install_selection" >&2 ;;
    esac
  done
}

build_mac() {
  echo
  echo "正在编译 Mac Catalyst App（${mac_configuration}）……"
  local build_command=(
    xcodebuild
    -project "$project_path"
    -scheme "$mac_scheme"
    -configuration "$mac_configuration"
    -destination "platform=macOS,variant=Mac Catalyst"
    -derivedDataPath "$mac_derived_data"
  )

  case "$mac_signing_mode" in
    adhoc)
      build_command+=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=-)
      ;;
    automatic)
      build_command+=(-allowProvisioningUpdates)
      if [[ -n $development_team ]]; then
        build_command+=("DEVELOPMENT_TEAM=$development_team")
      fi
      ;;
    *)
      echo "MAC_SIGNING_MODE 仅支持 adhoc 或 automatic：$mac_signing_mode" >&2
      exit 1
      ;;
  esac
  if [[ -n $bundle_id_override ]]; then
    build_command+=("PRODUCT_BUNDLE_IDENTIFIER=$bundle_id_override")
  fi
  "${build_command[@]}" build

  if [[ ! -d $mac_app_path ]]; then
    echo "编译完成，但找不到 App：$mac_app_path" >&2
    exit 1
  fi
  echo "macOS App 已构建：$mac_app_path"
}

build_and_launch_mac() {
  build_mac
  echo
  echo "正在启动 macOS App……"
  /usr/bin/open -n "$mac_app_path"
  echo "macOS App 已启动：$mac_app_path"
}

main() {
  local action=${1:-}
  if [[ $action == -h || $action == --help || $action == help ]]; then
    usage
    return
  fi
  if (( $# != 1 )); then
    usage >&2
    exit 1
  fi

  ensure_macos
  require_command xcodebuild
  require_command xcrun
  require_command plutil
  ensure_project_exists

  if [[ $action == install || $action == ios-clean || $action == iphone-clean || \
        $action == ios-overwrite || $action == iphone-overwrite ]]; then
    case "$ios_signing_mode" in
      manual)
        require_command security
        require_command openssl
        require_command base64
        require_command codesign
        ;;
      automatic) ;;
      *)
        echo "IOS_SIGNING_MODE 仅支持 manual 或 automatic：$ios_signing_mode" >&2
        exit 1
        ;;
    esac
  fi

  case "$action" in
    install) interactive_ios_install ;;
    ios-clean|iphone-clean) ios_clean_install ;;
    ios-overwrite|iphone-overwrite) ios_overwrite_install ;;
    devices) show_ios_devices ;;
    mac) build_and_launch_mac ;;
    mac-build) build_mac ;;
    *)
      echo "未知 Apple App 操作：$action" >&2
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
