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
  --ip IP             Optional: ping/connect-test a converter before launching
  --port PORT         Port for --ip (default: 23)
  --exe PATH          Windows path to seaView.exe
  --wineprefix PATH   WINEPREFIX to use (default: ~/.wine-seaview)
  -h, --help          Show this help

The converter address seaView uses is set inside seaView itself, under
Comms -> + -> Add a Serial Over Lan Port. See SETUP-GUIDE.md Part 7.
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
# [1/4] Wine present and new enough
# ---------------------------------------------------------------------------
echo "[1/4] Checking Wine..."
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
# [2/4] 64-bit prefix
#
# seaView.exe is a 64-bit binary. The installer is 32-bit and will install
# happily into a win32 prefix, leaving an application that can never start
# ("Bad EXE format") -- so check the prefix, not the installer.
# ---------------------------------------------------------------------------
echo "[2/4] Checking Wine environment..."
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
# [3/4] Phantom COM ports
#
# seaView polls every COM port Wine advertises, continuously, on the thread
# that draws its display -- regardless of whether it is using one. The kernel's
# 8250 driver invents 32 /dev/ttyS* nodes on hardware that has none, and the
# resulting scan drops the UI below 1 fps. Advisory: needs root and a reboot.
# ---------------------------------------------------------------------------
echo "[3/4] Checking for phantom serial ports..."
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
# [4/4] Converter reachable
#
# Courtesy only: seaView opens its own connection, so this just turns a
# confusing "no devices found" into an obvious network message.
# ---------------------------------------------------------------------------
echo "[4/4] Checking the converter..."
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

echo
echo "Launching seaView."
echo "  Connect to the sensor via  Comms -> +  ->  Add a Serial Over Lan Port"
echo "  (IP and port of your converter, Protocol TCP, Encoding Raw)"
echo

# ---------------------------------------------------------------------------
# Locate seaView.
#
# The installer is 32-bit, so Wine's wizard puts the application under
# "Program Files (x86)" by default, while a headless install given --root can
# put it under "Program Files". Both are normal, so look in both rather than
# assuming one -- and honour SEAVIEW_EXE / --exe first, which is the whole
# point of having that setting.
# ---------------------------------------------------------------------------
win_to_unix() {
    # C:\Program Files\...\seaView.exe  ->  $WINEPREFIX/drive_c/Program Files/.../seaView.exe
    local p="$1"
    p="${p#[A-Za-z]:}"
    printf '%s' "$WINEPREFIX/drive_c${p//\\//}"
}

SEAVIEW_PATH=""
if [ -n "${SEAVIEW_EXE:-}" ]; then
    cand=$(win_to_unix "$SEAVIEW_EXE")
    [ -f "$cand" ] && SEAVIEW_PATH="$cand"
fi
if [ -z "$SEAVIEW_PATH" ]; then
    for d in "$WINEPREFIX/drive_c/Program Files (x86)/Impact Subsea/seaView" \
             "$WINEPREFIX/drive_c/Program Files/Impact Subsea/seaView"; do
        [ -f "$d/seaView.exe" ] && { SEAVIEW_PATH="$d/seaView.exe"; break; }
    done
fi
if [ -z "$SEAVIEW_PATH" ]; then
    SEAVIEW_PATH=$(find "$WINEPREFIX/drive_c" -maxdepth 5 -name 'seaView.exe' -print -quit 2>/dev/null)
fi
if [ -z "$SEAVIEW_PATH" ]; then
    echo "  ERROR: seaView is not installed in $WINEPREFIX." >&2
    echo "         See SETUP-GUIDE.md Part 5. Looked in Program Files and" >&2
    echo "         Program Files (x86), and searched drive_c." >&2
    exit 1
fi

cd "$(dirname "$SEAVIEW_PATH")" || exit 1
exec wine "$(basename "$SEAVIEW_PATH")" "$@"
