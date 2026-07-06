#!/usr/bin/env bash
# Ensure alfred-vdroners.ddns.net exists in No-IP + ddclient (Forge webhook public URL).
set -euo pipefail

DOMAIN="${FORGE_WEBHOOK_DOMAIN:-alfred-vdroners.ddns.net}"
PUBLIC_IP="${PUBLIC_IP:-73.25.227.90}"

echo "=== Alfred Forge webhook DNS setup ==="

_in_ddclient=0
if sudo -n cat /etc/ddclient.conf 2>/dev/null | grep -q "${DOMAIN}"; then
  _in_ddclient=1
elif grep -q "${DOMAIN}" /etc/ddclient.conf 2>/dev/null; then
  _in_ddclient=1
fi

if [[ "$_in_ddclient" -eq 1 ]]; then
  echo "[ddclient] ${DOMAIN} already in /etc/ddclient.conf"
  python3 - "$DOMAIN" "$PUBLIC_IP" <<'PY' || true
import base64, re, subprocess, sys, urllib.parse, urllib.request
domain, ip = sys.argv[1:3]
try:
    conf = subprocess.check_output(["sudo", "-n", "cat", "/etc/ddclient.conf"], text=True)
except subprocess.CalledProcessError:
    sys.exit(0)
login = re.search(r"^login=(.+)$", conf, re.M).group(1).strip()
pw = re.search(r"^password='(.+)'$", conf, re.M).group(1)
url = f"https://dynupdate.no-ip.com/nic/update?hostname={urllib.parse.quote(domain)}&myip={ip}"
auth = base64.b64encode(f"{login}:{pw}".encode()).decode()
req = urllib.request.Request(url, headers={
    "Authorization": f"Basic {auth}",
    "User-Agent": "19labs OpenClaw-Alfred/1.0 dan@19labs.com",
})
with urllib.request.urlopen(req, timeout=20) as resp:
    body = resp.read().decode().strip()
print(f"[dynupdate] {body}")
if body.startswith("nohost"):
    print("[dynupdate] Create hostname at https://my.noip.com/dns/records/create-record")
    sys.exit(2)
PY
else
  echo "[ddclient] Adding ${DOMAIN} to /etc/ddclient.conf (requires sudo)..."
  if ! sudo -n true 2>/dev/null; then
    echo ""
    echo "MANUAL: Add this hostname to /etc/ddclient.conf (with the other vdroners hostnames):"
    echo "  ${DOMAIN}"
    echo "Then run:  sudo ddclient -force"
    echo ""
    echo "Also create the hostname in https://www.noip.com/ → A record → ${PUBLIC_IP}"
    exit 1
  fi
  sudo cp /etc/ddclient.conf "/etc/ddclient.conf.bak-alfred-forge-$(date +%Y%m%d%H%M)"
  if grep -q 'forge-vdroners\.ddns\.net' /etc/ddclient.conf; then
    sudo sed -i "s/forge-vdroners\.ddns.net/forge-vdroners.ddns.net, \\\n${DOMAIN}/" /etc/ddclient.conf
  else
    echo "  ${DOMAIN}" | sudo tee -a /etc/ddclient.conf >/dev/null
  fi
  sudo ddclient -force
  echo "[ddclient] Update sent to No-IP"
fi

RESOLVED="$(dig +short "${DOMAIN}" @8.8.8.8 | head -1 || true)"
if [[ -z "${RESOLVED}" ]]; then
  echo "[dns] PENDING — no public A record for ${DOMAIN} yet."
  echo "      Create it in No-IP if ddclient did not, then re-run:"
  echo "      bash scripts/setup-cpm-alfred-forge-webhook.sh"
  exit 2
fi
echo "[dns] OK — ${DOMAIN} → ${RESOLVED}"
echo "[dns] CPM + Let's Encrypt may take ~1–2 min after first resolve."
