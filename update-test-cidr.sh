#!/usr/bin/env bash
###############################################################################
# update-test-cidr.sh – set your current public IP in config.yaml test_cidrs
#
# First checks that you are NOT connected to Cato (the Cato DNS address
# 10.254.254.1 answers only through the Cato tunnel); if you are, it pauses so
# you can disconnect, since the lookup would otherwise return a Cato POP IP.
#
# Then detects the public IPv4 address (default: https://ifconfig.me) and writes it
# as <ip>/32 into the test_cidrs list of config.yaml. The entry managed by this
# script is tagged with "# auto-detected"; it is replaced on each run, so other
# (manual) entries are kept. If no tagged entry exists one is added. The
# documentation-range placeholder (203.0.113.0/24) is removed.
#
# Re-run ./iperf-ctl.sh create afterwards to push the new source to the
# security group.
#
# USAGE
#   ./update-test-cidr.sh [config-file]
#
# ENV
#   PUBLIC_IP_URL  – override the IP lookup service
#   CATO_DNS_IP    – address used to detect a Cato connection (default 10.254.254.1)
###############################################################################
set -euo pipefail

die() { printf '❌  %s\n' "$*" >&2; exit 1; }

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG_FILE="${1:-${CONFIG_FILE:-${BASE_DIR}/config.yaml}}"
IP_URL="${PUBLIC_IP_URL:-https://ifconfig.me}"
CATO_DNS_IP="${CATO_DNS_IP:-10.254.254.1}"

command -v curl >/dev/null    || die "curl is required"
command -v python3 >/dev/null || die "python3 is required"
[ -f "${CFG_FILE}" ] || die "Config file not found: ${CFG_FILE}"

# True (0) when the Cato DNS answers, i.e. the Cato client is connected.
cato_connected() {
  if command -v dig >/dev/null; then
    [ -n "$(dig +short +time=2 +tries=1 "@${CATO_DNS_IP}" example.com A 2>/dev/null)" ]
  elif command -v nslookup >/dev/null; then
    nslookup -timeout=2 -retry=1 example.com "${CATO_DNS_IP}" >/dev/null 2>&1
  else
    echo "⚠️   Neither dig nor nslookup found; skipping the Cato connection check" >&2
    return 1
  fi
}

while cato_connected; do
  echo "⚠️   Cato connection detected (DNS ${CATO_DNS_IP} answered): the public IP would be a Cato POP, not your own."
  [ -t 0 ] || die "Disconnect from Cato and run this script again"
  read -r -p "    Disconnect from Cato, then press Enter to re-check (q to quit): " answer
  case "${answer}" in q|Q) die "Aborted: still connected to Cato";; esac
done
echo "🔌  Not connected to Cato"

echo "🌐  Detecting public IP via ${IP_URL}"
ip=$(curl -4 --silent --show-error --fail --proto '=https' --max-time 10 "${IP_URL}" | tr -d '[:space:]') \
  || die "Could not determine the public IP"

python3 -I - "${CFG_FILE}" "${ip}" <<'PY'
import ipaddress, os, re, shutil, sys, tempfile

cfg, raw = sys.argv[1], sys.argv[2]
TAG = "# auto-detected"

try:
    ip = ipaddress.IPv4Address(raw)
except ValueError:
    sys.exit("❌  Lookup service returned an invalid IPv4 address: %r" % raw[:64])
cidr = "%s/32" % ip

lines = open(cfg).read().split("\n")
start = next((i for i, l in enumerate(lines) if re.match(r"test_cidrs\s*:", l)), None)
new_entry = "  - %-30s%s (%s)" % (cidr, TAG, "update-test-cidr.sh")

placeholder = ipaddress.ip_network("203.0.113.0/24")
def is_placeholder(line):
    m = re.match(r"\s*-\s*['\"]?([0-9./]+)", line)
    try:
        return bool(m) and ipaddress.ip_network(m.group(1), strict=False).subnet_of(placeholder)
    except ValueError:
        return False

if start is None:
    lines = lines[:] + ["test_cidrs:", new_entry]
else:
    end = start + 1
    while end < len(lines) and re.match(r"\s+-\s|\s*#", lines[end]) and lines[end].strip():
        end += 1
    block = [l for l in lines[start + 1:end] if not is_placeholder(l)]
    idx = next((i for i, l in enumerate(block) if TAG in l), None)
    if idx is not None:
        block[idx] = new_entry
    else:
        # keep trailing comment lines (if any) after the entries
        pos = len(block)
        while pos > 0 and block[pos - 1].lstrip().startswith("#"):
            pos -= 1
        block.insert(pos, new_entry)
    new_lines = lines[:start + 1] + block + lines[end:]
    if new_lines == lines:
        print("✅  test_cidrs already contains %s; nothing to update" % cidr)
        sys.exit(0)
    lines = new_lines

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(cfg)))
with os.fdopen(fd, "w") as f:
    f.write("\n".join(lines))
shutil.copymode(cfg, tmp)
os.replace(tmp, cfg)
print("✅  test_cidrs updated with %s in %s" % (cidr, cfg))
PY
echo "ℹ️   If test_cidrs changed, run ./iperf-ctl.sh create to apply it to the security group."
