#!/usr/bin/env bash
# Shared Nextcloud HTTP helpers with retry for Mail API warm-up (503/502/409).
# Source after load-nextcloud-env.sh.
set -euo pipefail

NC_HTTP_RETRIES="${NC_HTTP_RETRIES:-12}"
NC_HTTP_RETRY_DELAY="${NC_HTTP_RETRY_DELAY:-2}"

# Wait until Mail accounts API responds 2xx with OCS header.
nc_wait_mail_api() {
  local url="${NEXTCLOUD_URL:?NEXTCLOUD_URL not set}/index.php/apps/mail/api/accounts"
  local attempt code
  for ((attempt = 1; attempt <= NC_HTTP_RETRIES; attempt++)); do
    code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
      -u "${NEXTCLOUD_USER}:${NEXTCLOUD_PASS}" \
      -H 'Accept: application/json' \
      -H 'OCS-APIREQUEST: true' \
      "$url" 2>/dev/null || echo 000)
    if [[ "$code" =~ ^2 ]]; then
      return 0
    fi
    if [[ "$code" == "503" || "$code" == "502" || "$code" == "409" || "$code" == "000" ]]; then
      sleep "$NC_HTTP_RETRY_DELAY"
      continue
    fi
    echo "nc_wait_mail_api: unexpected HTTP $code (attempt $attempt/$NC_HTTP_RETRIES)" >&2
    return 1
  done
  echo "nc_wait_mail_api: mail API not ready after $NC_HTTP_RETRIES attempts (last=$code)" >&2
  return 1
}

# curl with retry; writes body to stdout. Sets NC_HTTP_CODE on success.
nc_curl_retry() {
  local attempt code tmp delay="$NC_HTTP_RETRY_DELAY"
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' RETURN
  for ((attempt = 1; attempt <= NC_HTTP_RETRIES; attempt++)); do
    code=$(curl -sS -o "$tmp" -w '%{http_code}' --max-time 30 "$@" 2>/dev/null || echo 000)
    NC_HTTP_CODE="$code"
    if [[ "$code" =~ ^2 ]]; then
      cat "$tmp"
      rm -f "$tmp"
      trap - RETURN
      return 0
    fi
    if [[ "$code" == "503" || "$code" == "502" || "$code" == "409" || "$code" == "000" ]]; then
      if (( attempt < NC_HTTP_RETRIES )); then
        sleep "$delay"
        delay=$(( delay < 6 ? delay + 1 : 6 ))
        continue
      fi
    fi
    cat "$tmp" >&2 || true
    rm -f "$tmp"
    trap - RETURN
    return 1
  done
}
