#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
IDENTITY="${HOME_LIBRARY_CODESIGN_IDENTITY:-}"
BUNDLE_ID="yu.homeLibrary.cloudkit-cli"
TEAM_ID="8VG8636JLY"
APP_IDENTIFIER="$TEAM_ID.$BUNDLE_ID"
CONTAINER_ID="iCloud.yu.homeLibrary"
CLOUDKIT_ENVIRONMENT="${HOME_LIBRARY_CLOUDKIT_ENVIRONMENT:-production}"
CLOUDKIT_ENVIRONMENT="$(printf '%s' "$CLOUDKIT_ENVIRONMENT" | tr '[:upper:]' '[:lower:]')"
case "$CLOUDKIT_ENVIRONMENT" in
  production|development) ;;
  *)
    printf '%s\n' "error: HOME_LIBRARY_CLOUDKIT_ENVIRONMENT must be production or development." >&2
    exit 2
    ;;
esac

find_matching_profile() {
  local target_app_id="$1"
  local target_container="$2"
  local home_dir
  home_dir="$HOME"
  local directories=(
    "$home_dir/Library/MobileDevice/Provisioning Profiles"
    "$home_dir/Library/Developer/Xcode/UserData/Provisioning Profiles"
  )
  local profile
  for directory in "${directories[@]}"; do
    [[ -d "$directory" ]] || continue
    while IFS= read -r profile; do
      if profile_matches "$profile" "$target_app_id" "$target_container"; then
        printf '%s\n' "$profile"
        return 0
      fi
    done < <(find "$directory" -maxdepth 1 \( -name '*.mobileprovision' -o -name '*.provisionprofile' \) -print 2>/dev/null)
  done
}

profile_matches() {
  local profile="$1"
  local target_app_id="$2"
  local target_container="$3"
  local plist
  plist="$(mktemp)"
  if ! security cms -D -i "$profile" > "$plist" 2>/dev/null; then
    rm -f "$plist"
    return 1
  fi

  local app_id
  app_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$plist" 2>/dev/null || true)"
  if [[ -z "$app_id" ]]; then
    app_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$plist" 2>/dev/null || true)"
  fi

  local platforms containers
  platforms="$(/usr/libexec/PlistBuddy -c 'Print :Platform' "$plist" 2>/dev/null || true)"
  containers="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.icloud-container-identifiers' "$plist" 2>/dev/null || true)"
  rm -f "$plist"

  [[ "$app_id" == "$target_app_id" ]] || return 1
  grep -Eq 'OSX|macOS' <<<"$platforms" || return 1
  grep -Fq "$target_container" <<<"$containers" || return 1
}

normalize_entitlements() {
  local path="$1"
  local cloudkit_environment="$2"
  local entitlement_environment="Production"
  if [[ "$cloudkit_environment" == "development" ]]; then
    entitlement_environment="Development"
  fi

  /usr/libexec/PlistBuddy -c 'Delete :application-identifier' "$path" 2>/dev/null || true

  /usr/libexec/PlistBuddy -c 'Delete :com.apple.application-identifier' "$path" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $APP_IDENTIFIER" "$path"

  /usr/libexec/PlistBuddy -c 'Delete :com.apple.developer.team-identifier' "$path" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$path"

  /usr/libexec/PlistBuddy -c 'Delete :com.apple.developer.icloud-services' "$path" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c 'Add :com.apple.developer.icloud-services array' "$path"
  /usr/libexec/PlistBuddy -c 'Add :com.apple.developer.icloud-services:0 string CloudKit' "$path"

  /usr/libexec/PlistBuddy -c 'Delete :com.apple.developer.icloud-container-identifiers' "$path" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c 'Add :com.apple.developer.icloud-container-identifiers array' "$path"
  /usr/libexec/PlistBuddy -c "Add :com.apple.developer.icloud-container-identifiers:0 string $CONTAINER_ID" "$path"

  /usr/libexec/PlistBuddy -c 'Delete :com.apple.developer.icloud-container-environment' "$path" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :com.apple.developer.icloud-container-environment string $entitlement_environment" "$path"

  /usr/libexec/PlistBuddy -c 'Delete :com.apple.developer.icloud-container-development-container-identifiers' "$path" 2>/dev/null || true
  if [[ "$cloudkit_environment" == "development" ]]; then
    /usr/libexec/PlistBuddy -c 'Add :com.apple.developer.icloud-container-development-container-identifiers array' "$path"
    /usr/libexec/PlistBuddy -c "Add :com.apple.developer.icloud-container-development-container-identifiers:0 string $CONTAINER_ID" "$path"
  fi
}

write_info_plist() {
  local path="$1"
  local bundle_id="$2"
  cat > "$path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>home-library-cloudkit</string>
  <key>CFBundleIdentifier</key>
  <string>$bundle_id</string>
  <key>CFBundleName</key>
  <string>home-library-cloudkit</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
</dict>
</plist>
PLIST
}

cd "$ROOT_DIR"
swift build --configuration "$CONFIGURATION" --product home-library-cloudkit >&2

BIN="$ROOT_DIR/.build/$CONFIGURATION/home-library-cloudkit"
if [[ -n "$IDENTITY" ]]; then
  PROFILE="$(find_matching_profile "$APP_IDENTIFIER" "$CONTAINER_ID")"
  if [[ -z "$PROFILE" ]]; then
    printf '%s\n' "error: no installed macOS provisioning profile matches $APP_IDENTIFIER and $CONTAINER_ID." >&2
    printf '%s\n' "Install a macOS development profile for bundle id $BUNDLE_ID with CloudKit container $CONTAINER_ID, then rerun this script." >&2
    exit 1
  fi

  APP="$ROOT_DIR/.build/$CONFIGURATION/home-library-cloudkit.app"
  APP_BIN="$APP/Contents/MacOS/home-library-cloudkit"
  RESOLVED_ENTITLEMENTS="$ROOT_DIR/.build/$CONFIGURATION/home-library-cloudkit.profile-entitlements.plist"
  PROFILE_PLIST="$(mktemp)"
  trap 'rm -f "$PROFILE_PLIST"' EXIT

  security cms -D -i "$PROFILE" > "$PROFILE_PLIST"
  /usr/libexec/PlistBuddy -x -c 'Print :Entitlements' "$PROFILE_PLIST" > "$RESOLVED_ENTITLEMENTS"
  normalize_entitlements "$RESOLVED_ENTITLEMENTS" "$CLOUDKIT_ENVIRONMENT"

  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS"
  cp "$BIN" "$APP_BIN"
  cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
  write_info_plist "$APP/Contents/Info.plist" "$BUNDLE_ID"

  codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --entitlements "$RESOLVED_ENTITLEMENTS" "$APP_BIN" >&2
  codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --entitlements "$RESOLVED_ENTITLEMENTS" "$APP" >&2
  printf '%s\n' "$APP_BIN"
else
  codesign --force --sign - "$BIN" >&2
  printf '%s\n' "warning: HOME_LIBRARY_CODESIGN_IDENTITY is not set; built an ad-hoc signed CLI without CloudKit entitlements." >&2
  printf '%s\n' "$BIN"
fi
