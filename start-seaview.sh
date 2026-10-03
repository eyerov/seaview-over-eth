#!/bin/bash
#
# start-seaview.sh
#
# Launches Impact Subsea seaView under Wine.
#
# seaView talks to the RS485-to-Ethernet converter itself, over TCP, using its
# own "Serial Over LAN" port. There is no bridge, no virtual serial port and no
# kernel module in the path:
#
#     ISA500 --RS485--> converter --TCP--> seaView
#
# So this script only has to get Wine right and start the application. The
# converter address is configured inside seaView, not here; CONVERTER_IP below
# is used solely for a reachability check before launch.
#
# The converter's address lives inside seaView, not here. --ip is available
# purely as an optional pre-launch reachability check when troubleshooting.
#
# Run ./start-seaview.sh --help for usage.

set -u

WINEPREFIX_DEFAULT="$HOME/.wine-seaview"
SEAVIEW_EXE='C:\Program Files\Impact Subsea\seaView\seaView.exe'
CONVERTER_IP=""
CONVERTER_PORT="23"
WINEPREFIX_OVERRIDE=""
CONFIG_FILE="$(dirname "$(readlink -f "$0")")/seaview.conf"

# Wine 9.x and earlier crash within seconds of seaView opening a serial port.
# seaView no longer needs one, but it still enumerates them, so the floor stays.
WINE_MIN_MAJOR=10

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --config FILE       Config file (default: ./seaview.conf if present)
  --ip IP             Converter address (overrides CONVERTER_IP in the config)
  --port PORT         Converter port (default: 23)
  --exe PATH          Windows path to seaView.exe
  --wineprefix PATH   WINEPREFIX to use (default: ~/.wine-seaview)
  -h, --help          Show this help

The converter address is written into seaView's settings before launch, so
its device search opens pre-filled. See SETUP-GUIDE.md Part 7.
EOF
}

ARGS=("$@")
for ((i=0; i<${#ARGS[@]}; i++)); do
    [ "${ARGS[$i]}" = "--config" ] && CONFIG_FILE="${ARGS[$((i+1))]}"
done

WINEPREFIX_FROM_CONFIG=""
if [ -f "$CONFIG_FILE" ]; then
    echo "Loading config: $CONFIG_FILE"
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    [ -n "${WINEPREFIX:-}" ] && WINEPREFIX_FROM_CONFIG="$WINEPREFIX"
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --config)     shift 2 ;;
        --ip)         CONVERTER_IP="$2"; shift 2 ;;
        --port)       CONVERTER_PORT="$2"; shift 2 ;;
        --exe)        SEAVIEW_EXE="$2"; shift 2 ;;
        --wineprefix) WINEPREFIX_OVERRIDE="$2"; shift 2 ;;
        -h|--help)    usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

# WINEPREFIX: flag > config > environment > our own default.
# Deliberately not ~/.wine, which is 32-bit on a stock Ubuntu install.
if   [ -n "$WINEPREFIX_OVERRIDE" ];   then export WINEPREFIX="$WINEPREFIX_OVERRIDE"
elif [ -n "$WINEPREFIX_FROM_CONFIG" ]; then export WINEPREFIX="$WINEPREFIX_FROM_CONFIG"
elif [ -n "${WINEPREFIX:-}" ];        then :
else export WINEPREFIX="$WINEPREFIX_DEFAULT"
fi
export WINEDEBUG="${WINEDEBUG:--all}"
echo "Using WINEPREFIX: $WINEPREFIX"

# ---------------------------------------------------------------------------
# [1/5] Wine present and new enough
# ---------------------------------------------------------------------------
echo "[1/5] Checking Wine..."
if ! command -v wine >/dev/null 2>&1; then
    echo "  ERROR: wine is not installed. See SETUP-GUIDE.md Part 3." >&2
    exit 1
fi
WINE_VER_RAW="$(wine --version 2>/dev/null | head -1)"
WINE_MAJOR="$(printf '%s' "$WINE_VER_RAW" | sed -n 's/^wine-\([0-9]\{1,\}\).*/\1/p')"
if [ -z "$WINE_MAJOR" ]; then
    echo "  WARNING: could not parse Wine version from '$WINE_VER_RAW'; continuing." >&2
elif [ "$WINE_MAJOR" -lt "$WINE_MIN_MAJOR" ]; then
    cat >&2 <<EOF
  ERROR: Wine $WINE_VER_RAW is too old; seaView needs ${WINE_MIN_MAJOR}.0 or newer.
         Ubuntu's own package is 9.0. Install WineHQ's build -- SETUP-GUIDE.md Part 3.
EOF
    exit 1
fi
echo "  $WINE_VER_RAW (OK)"

# ---------------------------------------------------------------------------
# [2/5] 64-bit prefix
#
# seaView.exe is a 64-bit binary. The installer is 32-bit and will install
# happily into a win32 prefix, leaving an application that can never start
# ("Bad EXE format") -- so check the prefix, not the installer.
# ---------------------------------------------------------------------------
echo "[2/5] Checking Wine environment..."
if [ -f "$WINEPREFIX/system.reg" ]; then
    if ! head -5 "$WINEPREFIX/system.reg" | grep -q '#arch=win64'; then
        cat >&2 <<EOF
  ERROR: $WINEPREFIX is 32-bit, but seaView.exe is 64-bit ("Bad EXE format").
         Recreate it:
           WINEARCH=win64 WINEPREFIX="$WINEPREFIX" WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -u
EOF
        exit 1
    fi
    echo "  64-bit prefix (OK)"
else
    echo "  Prefix does not exist; creating it as 64-bit..."
    WINEARCH=win64 WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -u >/dev/null 2>&1 \
        || { echo "  ERROR: failed to create prefix." >&2; exit 1; }
fi

# ---------------------------------------------------------------------------
# [3/5] Phantom COM ports
#
# seaView polls every COM port Wine advertises, continuously, on the thread
# that draws its display -- regardless of whether it is using one. The kernel's
# 8250 driver invents 32 /dev/ttyS* nodes on hardware that has none, and the
# resulting scan drops the UI below 1 fps. Advisory: needs root and a reboot.
# ---------------------------------------------------------------------------
echo "[3/5] Checking for phantom serial ports..."
N_TTYS=$(ls /dev/ttyS* 2>/dev/null | wc -l)
N_USB=$(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | wc -l)
if [ "$((N_TTYS + N_USB))" -gt 0 ]; then
    cat >&2 <<EOF
  NOTE: Wine will expose $((N_TTYS + N_USB)) serial port(s) (${N_TTYS} x ttyS, ${N_USB} x ttyUSB/ACM).
        seaView polls every port it can see, which makes the UI sluggish even
        though it talks to the sensor over the network. If this machine has no
        real onboard serial hardware, remove them -- SETUP-GUIDE.md Part 6:
            8250.nr_uarts=0        (check: cat /sys/class/tty/ttyS0/type -> 0)
EOF
else
    echo "  None (as designed)."
fi

# ---------------------------------------------------------------------------
# [4/5] Converter reachable
#
# Courtesy only: seaView opens its own connection, so this just turns a
# confusing "no devices found" into an obvious network message.
# ---------------------------------------------------------------------------
echo "[4/5] Checking the converter..."
if [ -z "$CONVERTER_IP" ]; then
    echo "  Skipped -- pass --ip <address> to test a converter before launching."
else
    # A plain TCP connect, not a data read: once seaView has put the sensor
    # into binary mode it stays silent until polled, so waiting for bytes
    # would report a healthy link as broken.
    if ! ping -c 1 -W 2 "$CONVERTER_IP" >/dev/null 2>&1; then
        echo "  WARNING: ${CONVERTER_IP} does not respond to ping." >&2
        echo "           seaView will not find the sensor until this is fixed." >&2
    elif timeout 3 bash -c "exec 3<>/dev/tcp/${CONVERTER_IP}/${CONVERTER_PORT}" 2>/dev/null; then
        echo "  ${CONVERTER_IP}:${CONVERTER_PORT} reachable, accepting connections."
    else
        echo "  WARNING: ${CONVERTER_IP} pings, but port ${CONVERTER_PORT} refused the connection." >&2
        echo "           Check the port number, and that nothing else is holding the" >&2
        echo "           converter -- most serve only one session at a time." >&2
    fi
fi

# ---------------------------------------------------------------------------
# [5/5] Pre-fill seaView's device search with the converter address.
#
# seaView keeps its settings in seaview.xml and reads searchIp / searchIpPort
# at startup. Writing them here means the Devices search opens pointed at the
# network with the address already in place, instead of the operator typing it.
#
# It stops one click short of connecting: seaView still needs Search pressed.
# There is no command-line or settings route to create the Serial Over LAN
# port itself -- seaView exposes neither.
#
# Only safe while seaView is not running: it rewrites this file on exit.
# ---------------------------------------------------------------------------
echo "[5/5] Pre-filling seaView's device search..."
SEAVIEW_XML="$WINEPREFIX/drive_c/users/$USER/AppData/Roaming/Impact Subsea/seaView/seaview.xml"
if [ -z "$CONVERTER_IP" ]; then
    echo "  Skipped (no CONVERTER_IP set)."
elif [ ! -f "$SEAVIEW_XML" ]; then
    echo "  Skipped -- seaView has not created its settings file yet."
    echo "  Run seaView once, close it, and this will work from then on."
elif pgrep -x seaView.exe >/dev/null 2>&1; then
    echo "  Skipped -- seaView is already running (it would overwrite the file)." >&2
else
    python3 - "$SEAVIEW_XML" "$CONVERTER_IP" "$CONVERTER_PORT" <<'PYEOF'
import re, sys
path, ip, port = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    s = open(path, encoding="utf-8").read()
except OSError as e:
    print(f"  Could not read seaView settings: {e}"); raise SystemExit(0)
orig = s
s = re.sub(r"<searchIp>.*?</searchIp>",     f"<searchIp>{ip}</searchIp>",       s, count=1)
s = re.sub(r"<searchIpPort>.*?</searchIpPort>", f"<searchIpPort>{port}</searchIpPort>", s, count=1)
s = re.sub(r"<searchOpen>.*?</searchOpen>", "<searchOpen>true</searchOpen>",    s, count=1)
if s == orig:
    print("  seaView settings did not contain the expected fields; left alone.")
else:
    open(path, "w", encoding="utf-8").write(s)
    print(f"  Search will open on NETWORK, {ip}:{port}.")
PYEOF
fi

echo
echo "Launching seaView."
if [ -n "$CONVERTER_IP" ]; then
    echo "  In Devices, press Search -- the address is already filled in."
    echo "  Or add the port manually: Comms -> + -> Add a Serial Over Lan Port"
    echo "  (${CONVERTER_IP}, ${CONVERTER_PORT}, Protocol TCP, Encoding Raw)"
else
    echo "  Connect via  Comms -> +  ->  Add a Serial Over Lan Port"
    echo "  (IP and port of your converter, Protocol TCP, Encoding Raw)"
fi
echo

cd "$WINEPREFIX/drive_c/Program Files/Impact Subsea/seaView" 2>/dev/null \
    || { echo "ERROR: seaView is not installed in $WINEPREFIX -- see SETUP-GUIDE.md Part 5." >&2; exit 1; }
exec wine seaView.exe "$@"
