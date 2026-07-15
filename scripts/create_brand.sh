#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Uso (criar nova marca completa Android+iOS):
  ./scripts/create_brand.sh \
    --key rmrastreadores \
    --name "RM Rastreadores" \
    --id com.rmrastreadores \
    --url https://rastrear.rmrastreadores.com/ \
    [--android-version-code 1] \
    [--ios-marketing-version 1.0] \
    [--icon /caminho/AppIcon-1024.png]

Uso (sincronizar marca ja criada nos arquivos Android+iOS):
  ./scripts/create_brand.sh --key rmrastreadores --sync-existing

O script faz automaticamente:
- branding/<key>/Branding.properties (quando nova marca)
- branding/<key>/AppIcon-1024.png (quando nova marca)
- android/app/build.gradle.kts (loadBrandingConfig + productFlavor)
- ios/WhiteLabelConfig.swift (fallback config)
USAGE
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Erro: comando obrigatorio nao encontrado: $1" >&2
    exit 1
  fi
}

prop_get() {
  local key="$1"
  local file="$2"
  grep -E "^${key}=" "$file" | head -n1 | cut -d= -f2-
}

to_var_name() {
  local raw="$1"
  local sanitized
  sanitized="$(echo "$raw" | sed -E 's/[^a-zA-Z0-9]+/_/g')"
  if [[ "$sanitized" =~ ^[0-9] ]]; then
    sanitized="brand_${sanitized}"
  fi
  echo "${sanitized}Branding"
}

to_flavor_name() {
  local key="$1"
  echo "${key^}"
}

update_android_gradle() {
  local key="$1"
  local var_name="$2"
  local file="$3"
  local tmp_file
  tmp_file="$(mktemp)"

  if [[ ! -f "$file" ]]; then
    echo "Aviso: arquivo nao encontrado para auto update: $file" >&2
    return
  fi

  if ! grep -q "loadBrandingConfig(\"$key\")" "$file"; then
    awk -v newline="val ${var_name} = loadBrandingConfig(\"${key}\")" '
      { lines[NR] = $0 }
      END {
        last = 0
        for (i = 1; i <= NR; i++) {
          if (lines[i] ~ /^val [a-zA-Z0-9_]+Branding = loadBrandingConfig\("[a-z0-9]+"\)/) {
            last = i
          }
        }

        if (last == 0) {
          for (i = 1; i <= NR; i++) print lines[i]
          print newline
          exit
        }

        for (i = 1; i <= NR; i++) {
          print lines[i]
          if (i == last) print newline
        }
      }
    ' "$file" > "$tmp_file"
    mv "$tmp_file" "$file"
  fi

  if ! grep -q "create(\"$key\")" "$file"; then
    awk -v key="$key" -v var_name="$var_name" '
      function print_flavor_block() {
        print "        create(\"" key "\") {"
        print "            dimension = \"brand\""
        print "            applicationId = " var_name ".androidApplicationId"
        print "            versionCode = " var_name ".androidVersionCode"
        print "            versionName = " var_name ".androidVersionName"
        print "            resValue(\"string\", \"app_name\", " var_name ".appName)"
        print "            resValue(\"string\", \"string_site\", " var_name ".siteURL)"
        print "        }"
      }

      {
        line = $0
        open_count = gsub(/\{/, "{", line)
        close_count = gsub(/\}/, "}", line)

        if ($0 ~ /^[[:space:]]*productFlavors[[:space:]]*\{/) {
          in_pf = 1
          pf_depth = 1
          print $0
          next
        }

        if (in_pf == 1 && inserted == 0 && pf_depth == 1 && $0 ~ /^[[:space:]]*}/) {
          print ""
          print_flavor_block()
          inserted = 1
        }

        print $0

        if (in_pf == 1) {
          pf_depth += open_count - close_count
          if (pf_depth == 0) in_pf = 0
        }
      }
    ' "$file" > "$tmp_file"
    mv "$tmp_file" "$file"
  fi
}

update_ios_whitelabel() {
  local key="$1"
  local app_name="$2"
  local site_url="$3"
  local allowed_host="$4"
  local file="$5"
  local tmp_file
  tmp_file="$(mktemp)"

  if [[ ! -f "$file" ]]; then
    echo "Aviso: arquivo nao encontrado para auto update: $file" >&2
    return
  fi

  if grep -q "\"$key\": WhiteLabelConfig(" "$file"; then
    return
  fi

  awk -v key="$key" -v app_name="$app_name" -v site_url="$site_url" -v allowed_host="$allowed_host" '
    { lines[NR] = $0 }
    END {
      start = 0
      close_idx = 0
      for (i = 1; i <= NR; i++) {
        if (lines[i] ~ /private static let configs: \[String: WhiteLabelConfig\] = \[/) {
          start = i
          break
        }
      }

      if (start == 0) {
        for (i = 1; i <= NR; i++) print lines[i]
        exit
      }

      for (i = start + 1; i <= NR; i++) {
        if (lines[i] ~ /^[[:space:]]*]/) {
          close_idx = i
          break
        }
      }

      if (close_idx == 0) {
        for (i = 1; i <= NR; i++) print lines[i]
        exit
      }

      last_paren = 0
      for (i = close_idx - 1; i > start; i--) {
        if (lines[i] ~ /^[[:space:]]*\)[[:space:]]*$/) {
          last_paren = i
          break
        }
      }

      if (last_paren > 0 && lines[last_paren] !~ /,[[:space:]]*$/) {
        lines[last_paren] = lines[last_paren] ","
      }

      for (i = 1; i < close_idx; i++) print lines[i]
      print "        \"" key "\": WhiteLabelConfig("
      print "            key: \"" key "\"," 
      print "            appName: \"" app_name "\"," 
      print "            siteURL: URL(string: \"" site_url "\")!,"
      print "            allowedHost: \"" allowed_host "\""
      print "        )"
      print lines[close_idx]
      for (i = close_idx + 1; i <= NR; i++) print lines[i]
    }
  ' "$file" > "$tmp_file"

  mv "$tmp_file" "$file"
}

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_GRADLE_FILE="$PROJECT_ROOT/android/app/build.gradle.kts"
IOS_CONFIG_FILE="$PROJECT_ROOT/ios/WhiteLabelConfig.swift"

KEY=""
APP_NAME=""
APP_ID=""
SITE_URL=""
ALLOWED_HOST=""
ANDROID_VERSION_CODE=""
IOS_MARKETING_VERSION="1.0"
ICON_SOURCE=""
SYNC_EXISTING="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --key) KEY="${2:-}"; shift 2 ;;
    --name) APP_NAME="${2:-}"; shift 2 ;;
    --id) APP_ID="${2:-}"; shift 2 ;;
    --url) SITE_URL="${2:-}"; shift 2 ;;
    --android-version-code) ANDROID_VERSION_CODE="${2:-}"; shift 2 ;;
    --ios-marketing-version) IOS_MARKETING_VERSION="${2:-}"; shift 2 ;;
    --icon) ICON_SOURCE="${2:-}"; shift 2 ;;
    --sync-existing) SYNC_EXISTING="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Argumento invalido: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$KEY" ]]; then
  echo "Erro: --key e obrigatorio." >&2
  usage
  exit 1
fi

if [[ ! "$KEY" =~ ^[a-z][a-z0-9]*$ ]]; then
  echo "Erro: --key deve ter apenas letras minusculas e numeros, iniciando com letra." >&2
  exit 1
fi

require_cmd sed
require_cmd grep
require_cmd awk
require_cmd mktemp

BRANDING_DIR="$PROJECT_ROOT/branding/$KEY"
BRANDING_FILE="$BRANDING_DIR/Branding.properties"

if [[ -d "$BRANDING_DIR" ]]; then
  if [[ "$SYNC_EXISTING" != "true" ]]; then
    echo "Erro: a marca '$KEY' ja existe em branding/$KEY. Use --sync-existing para sincronizar arquivos." >&2
    exit 1
  fi

  if [[ ! -f "$BRANDING_FILE" ]]; then
    echo "Erro: arquivo ausente em marca existente: $BRANDING_FILE" >&2
    exit 1
  fi

  APP_NAME="$(prop_get appName "$BRANDING_FILE")"
  APP_ID="$(prop_get iosBundleId "$BRANDING_FILE")"
  SITE_URL="$(prop_get siteURL "$BRANDING_FILE")"
  ALLOWED_HOST="$(prop_get allowedHost "$BRANDING_FILE")"
  IOS_MARKETING_VERSION="$(prop_get iosMarketingVersion "$BRANDING_FILE")"
  ANDROID_VERSION_CODE="$(prop_get androidVersionCode "$BRANDING_FILE")"
else
  if [[ -z "$APP_NAME" || -z "$APP_ID" || -z "$SITE_URL" ]]; then
    echo "Erro: para nova marca, --name, --id e --url sao obrigatorios." >&2
    usage
    exit 1
  fi

  if [[ ! "$APP_ID" =~ ^[a-zA-Z0-9]+(\.[a-zA-Z0-9]+)+$ ]]; then
    echo "Erro: --id invalido. Exemplo: com.atualizasom" >&2
    exit 1
  fi

  if [[ ! "$SITE_URL" =~ ^https?:// ]]; then
    echo "Erro: --url deve comecar com http:// ou https://" >&2
    exit 1
  fi

  if [[ -n "$ANDROID_VERSION_CODE" && ! "$ANDROID_VERSION_CODE" =~ ^[0-9]+$ ]]; then
    echo "Erro: --android-version-code deve ser numero inteiro." >&2
    exit 1
  fi

  if [[ ! "$IOS_MARKETING_VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    echo "Erro: --ios-marketing-version invalido. Exemplo: 1.0" >&2
    exit 1
  fi

  if [[ -z "$ICON_SOURCE" ]]; then
    ICON_SOURCE="$PROJECT_ROOT/branding/quarkgps/AppIcon-1024.png"
  fi

  if [[ ! -f "$ICON_SOURCE" ]]; then
    echo "Erro: icone nao encontrado em: $ICON_SOURCE" >&2
    exit 1
  fi

  if [[ -z "$ANDROID_VERSION_CODE" ]]; then
    max_code=0
    while IFS= read -r file; do
      code_line="$(grep -E '^androidVersionCode=' "$file" || true)"
      code="${code_line#androidVersionCode=}"
      if [[ "$code" =~ ^[0-9]+$ ]] && (( code > max_code )); then
        max_code="$code"
      fi
    done < <(find "$PROJECT_ROOT/branding" -mindepth 2 -maxdepth 2 -type f -name 'Branding.properties' | sort)

    ANDROID_VERSION_CODE=$((max_code + 1))
  fi

  ALLOWED_HOST="$(echo "$SITE_URL" | sed -E 's#^[a-zA-Z]+://##; s#/.*$##')"

  mkdir -p "$BRANDING_DIR"
  cat > "$BRANDING_FILE" <<BRAND
# Geral
key=$KEY
appName=$APP_NAME
siteURL=$SITE_URL
allowedHost=$ALLOWED_HOST

# iOS
iosBundleId=$APP_ID
iosMarketingVersion=$IOS_MARKETING_VERSION

# Android
androidApplicationId=$APP_ID
androidVersionCode=$ANDROID_VERSION_CODE
androidVersionName=\${androidVersionCode}.0
BRAND

  cp "$ICON_SOURCE" "$BRANDING_DIR/AppIcon-1024.png"
fi

VAR_NAME="$(to_var_name "$KEY")"
FLAVOR_NAME="$(to_flavor_name "$KEY")"

update_android_gradle "$KEY" "$VAR_NAME" "$ANDROID_GRADLE_FILE"
update_ios_whitelabel "$KEY" "$APP_NAME" "$SITE_URL" "$ALLOWED_HOST" "$IOS_CONFIG_FILE"

cat <<MSG

Marca sincronizada com sucesso:
- branding/$KEY/Branding.properties
- branding/$KEY/AppIcon-1024.png (quando nova marca)
- android/app/build.gradle.kts
- ios/WhiteLabelConfig.swift

Build APK por terminal:
  cd android
  bash gradlew :app:assemble${FLAVOR_NAME}Debug
MSG
