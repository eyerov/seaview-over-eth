#!/bin/bash
#
# start-seaview.sh
#
# Brings up a serial link into Impact Subsea seaView running under Wine, and
# launches the application.
#
# Two transports are supported:
#
#   TRANSPORT="ethernet"   RS485-to-Ethernet converter -> socat -> tty0tty
#                          virtual null-modem pair -> Wine COM port.
#                          This is the FMD deployment architecture.
#
#   TRANSPORT="usb"        USB serial adapter -> Wine COM port directly.
#                          For bench work with a USB RS232/RS485 adapter.
#
# Settings come from (in order of increasing priority):
#   1. built-in defaults (below)
#   2. a config file (./seaview.conf, or one passed with --config)
#   3. command-line flags
#   4. auto-detection, where possible, for anything still unset
#
# Run ./start-seaview.sh --help for usage.

set -u

# ---------------------------------------------------------------------------
# Built-in defaults
# ---------------------------------------------------------------------------
TRANSPORT="ethernet"
CONVERTER_IP=""
CONVERTER_PORT="2000"
TNT_PAIR=""
WINE_COM_PORT="COM10"
SEAVIEW_EXE='C:\Program Files\Impact Subsea\seaView\seaView.exe'
USB_PORT=""
WINEPREFIX_OVERRIDE=""
SOCAT_LOG="/tmp/socat-seaview.log"
CONFIG_FILE="$(dirname "$(readlink -f "$0")")/seaview.conf"

# Where install-tty0tty.sh stages the tty0tty source tree by default.
# Keep in sync with INSTALL_DIR in install-tty0tty.sh.
TTY0TTY_HOME="${TTY0TTY_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/tty0tty}"
TTY0TTY_DIR=""

# Minimum Wine version. Wine 9.x and earlier crash within seconds of opening
# a serial port -- see README "Wine version requirement".
WINE_MIN_MAJOR=10

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --config FILE         Path to config file (default: ./seaview.conf if present)
  --transport MODE      "ethernet" (converter + tty0tty) or "usb" (direct adapter)
  --ip IP               Converter IP address (ethernet transport; required)
  --port PORT           Converter TCP port (default: 2000)
  --tnt-pair N          tty0tty pair index: 0, 2, 4, or 6 (default: auto-detect)
  --usb-port PATH       Serial device for usb transport (default: auto-detect by-id)
  --com PORT            Wine COM port name, e.g. COM10 (default: COM10)
  --exe PATH            Windows path to seaView.exe
  --wineprefix PATH     WINEPREFIX to use (default: \$WINEPREFIX, else ~/.wine-seaview)
  --tty0tty-dir PATH    Path to the tty0tty source tree or its module/ directory
  -h, --help            Show this help

Config file format (seaview.conf, same directory as this script):
  TRANSPORT="ethernet"
  CONVERTER_IP="192.168.2.125"
  CONVERTER_PORT="2000"
  WINE_COM_PORT="COM10"
  SEAVIEW_EXE='C:\\Program Files\\Impact Subsea\\seaView\\seaView.exe'
  WINEPREFIX="\$HOME/.wine-seaview"
EOF
}

# ---------------------------------------------------------------------------
# Parse a leading --config flag first (so we know which file to source)
# ---------------------------------------------------------------------------
ARGS=("$@")
for ((i=0; i<${#ARGS[@]}; i++)); do
    if [ "${ARGS[$i]}" = "--config" ]; then
        CONFIG_FILE="${ARGS[$((i+1))]}"
    fi
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
        --config)       shift 2 ;;   # already handled above
        --transport)    TRANSPORT="$2"; shift 2 ;;
        --ip)           CONVERTER_IP="$2"; shift 2 ;;
        --port)         CONVERTER_PORT="$2"; shift 2 ;;
        --tnt-pair)     TNT_PAIR="$2"; shift 2 ;;
        --usb-port)     USB_PORT="$2"; shift 2 ;;
        --com)          WINE_COM_PORT="$2"; shift 2 ;;
        --exe)          SEAVIEW_EXE="$2"; shift 2 ;;
        --wineprefix)   WINEPREFIX_OVERRIDE="$2"; shift 2 ;;
        --tty0tty-dir)  TTY0TTY_DIR="$2"; shift 2 ;;
        -h|--help)      usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Resolve WINEPREFIX (flag > config > env var > our own default)
#
# Note the default differs from Wine's: seaView needs a 64-bit prefix, and
# a pre-existing ~/.wine is very often 32-bit, so we keep our own.
# ---------------------------------------------------------------------------
if [ -n "$WINEPREFIX_OVERRIDE" ]; then
    export WINEPREFIX="$WINEPREFIX_OVERRIDE"
elif [ -n "$WINEPREFIX_FROM_CONFIG" ]; then
    export WINEPREFIX="$WINEPREFIX_FROM_CONFIG"
elif [ -n "${WINEPREFIX:-}" ]; then
    :
else
    export WINEPREFIX="$HOME/.wine-seaview"
fi
export WINEDEBUG="${WINEDEBUG:--all}"
echo "Using WINEPREFIX: $WINEPREFIX"

# ---------------------------------------------------------------------------
# Preflight: external commands
# ---------------------------------------------------------------------------
MISSING_PKGS=""
if ! command -v wine >/dev/null 2>&1; then
    echo "ERROR: 'wine' is not installed - it runs seaView." >&2
    MISSING_PKGS="$MISSING_PKGS wine"
fi
if [ "$TRANSPORT" = "ethernet" ] && ! command -v socat >/dev/null 2>&1; then
    echo "ERROR: 'socat' is not installed - it provides the network-to-serial bridge." >&2
    MISSING_PKGS="$MISSING_PKGS socat"
fi
if [ -n "$MISSING_PKGS" ]; then
    echo >&2
    echo "Install the missing package(s) with:" >&2
    echo "    sudo apt update && sudo apt install -y$MISSING_PKGS" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Preflight: Wine version.
#
# Wine <= 9.x implements WaitCommEvent by spawning a worker thread per wait
# (dlls/ntdll/unix/serial.c). That thread can start with a null argument and
# faults on its first dereference, killing seaView within ~10 seconds of it
# opening a port. Wine 10 replaced the whole path with server-side async I/O.
# This is not a warning: on Wine 9 the application cannot be used at all.
# ---------------------------------------------------------------------------
WINE_VER_RAW="$(wine --version 2>/dev/null | head -1)"
WINE_MAJOR="$(printf '%s' "$WINE_VER_RAW" | sed -n 's/^wine-\([0-9]\{1,\}\).*/\1/p')"
if [ -z "$WINE_MAJOR" ]; then
    echo "WARNING: could not parse Wine version from '$WINE_VER_RAW'; continuing." >&2
elif [ "$WINE_MAJOR" -lt "$WINE_MIN_MAJOR" ]; then
    cat >&2 <<EOF
ERROR: Wine $WINE_VER_RAW is too old. seaView needs Wine ${WINE_MIN_MAJOR}.0 or newer.

  Wine 9 and earlier crash a few seconds after seaView opens a serial port:
      Unhandled exception: page fault on read access to 0x0000000000000000

  Ubuntu's own 'wine' package is 9.0. Install WineHQ's build instead:
      sudo mkdir -pm755 /etc/apt/keyrings
      sudo wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
      sudo wget -NP /etc/apt/sources.list.d/ \\
          https://dl.winehq.org/wine-builds/ubuntu/dists/\$(lsb_release -cs)/winehq-\$(lsb_release -cs).sources
      sudo apt update && sudo apt install --install-recommends winehq-stable
EOF
    exit 1
fi
echo "Wine version: $WINE_VER_RAW (OK)"

# ---------------------------------------------------------------------------
# Preflight: the prefix must be 64-bit.
#
# seaView.exe is a PE32+ x86-64 binary. The *installer* is 32-bit and will
# happily run in a win32 prefix, leaving behind an application that can never
# start ("Bad EXE format") -- so check the prefix, not the installer.
# ---------------------------------------------------------------------------
if [ -f "$WINEPREFIX/system.reg" ]; then
    if ! head -5 "$WINEPREFIX/system.reg" | grep -q '#arch=win64'; then
        cat >&2 <<EOF
ERROR: $WINEPREFIX is a 32-bit Wine prefix, but seaView.exe is 64-bit.
       Launching it there fails with "Bad EXE format".

  Create a 64-bit prefix and reinstall seaView into it:
      WINEARCH=win64 WINEPREFIX="$WINEPREFIX" WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -u
EOF
        exit 1
    fi
else
    echo "Prefix $WINEPREFIX does not exist yet; creating it as win64..."
    WINEARCH=win64 WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -u >/dev/null 2>&1 \
        || { echo "ERROR: failed to create prefix." >&2; exit 1; }
fi

# ---------------------------------------------------------------------------
# Preflight: phantom serial ports.
#
# seaView opens and polls EVERY COM port Wine advertises, continuously. The
# kernel's 8250 driver creates 32 /dev/ttyS* nodes even on machines with no
# serial hardware, Wine turns each into a COM port, and the resulting scan
# saturates seaView's GUI thread -- the UI drops to well under 1 fps.
#
# Advisory only: it needs root to change, and seaView still works, just
# slowly.
# ---------------------------------------------------------------------------
NR_UARTS="$(cat /sys/module/8250/parameters/nr_uarts 2>/dev/null || echo 0)"
if [ "$NR_UARTS" -gt 4 ] 2>/dev/null; then
    TTYS_COUNT=$(ls /dev/ttyS* 2>/dev/null | wc -l)
    cat >&2 <<EOF
NOTE: the kernel is exposing $TTYS_COUNT /dev/ttyS* ports (8250.nr_uarts=$NR_UARTS).
      seaView polls every COM port Wine advertises, so these phantom ports
      make the UI sluggish. If this machine has no real onboard serial
      hardware, reduce them:
          echo 1 | sudo tee /sys/module/8250/parameters/nr_uarts
      or permanently, via the kernel command line:
          8250.nr_uarts=1      (see README "Phantom COM ports")

EOF
fi

# ---------------------------------------------------------------------------
# Validate transport-specific settings
# ---------------------------------------------------------------------------
case "$TRANSPORT" in
    ethernet)
        if [ -z "$CONVERTER_IP" ]; then
            echo "ERROR: converter IP not set. Use --ip, or set CONVERTER_IP in $CONFIG_FILE" >&2
            exit 1
        fi
        ;;
    usb) ;;
    *)
        echo "ERROR: unknown TRANSPORT '$TRANSPORT' (expected 'ethernet' or 'usb')." >&2
        exit 1
        ;;
esac

if [ -z "$SEAVIEW_EXE" ]; then
    echo "ERROR: seaView path not set. Use --exe, or set SEAVIEW_EXE in $CONFIG_FILE" >&2
    exit 1
fi

# ===========================================================================
# USB transport: map the adapter straight to the Wine COM port and launch.
# ===========================================================================
if [ "$TRANSPORT" = "usb" ]; then
    echo "[1/2] Selecting USB serial adapter..."
    if [ -z "$USB_PORT" ]; then
        # Prefer the stable by-id name: /dev/ttyUSB* renumbers on replug.
        USB_PORT=$(ls -1 /dev/serial/by-id/* 2>/dev/null | head -n1)
        [ -z "$USB_PORT" ] && USB_PORT=$(ls -1 /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | sort -V | head -n1)
    fi
    if [ -z "$USB_PORT" ] || [ ! -e "$USB_PORT" ]; then
        echo "  ERROR: no USB serial adapter found. Plug it in, or pass --usb-port." >&2
        exit 1
    fi
    echo "  Using: $USB_PORT ($(readlink -f "$USB_PORT"))"

    echo "[2/2] Mapping Wine ${WINE_COM_PORT} -> ${USB_PORT} ..."
    wine reg add "HKLM\\Software\\Wine\\Ports" /v "$WINE_COM_PORT" /t REG_SZ /d "$USB_PORT" /f >/dev/null 2>&1
    wineserver -k 2>/dev/null; sleep 1
    wineboot -u >/dev/null 2>&1

    echo "Launching seaView (select ${WINE_COM_PORT} in its port settings)..."
    echo
    exec wine "$SEAVIEW_EXE"
fi

# ===========================================================================
# Ethernet transport: converter -> socat -> tty0tty pair -> Wine COM port.
# ===========================================================================

# ---------------------------------------------------------------------------
# 1. Make sure the tty0tty kernel module is loaded
# ---------------------------------------------------------------------------
echo "[1/8] Checking tty0tty module..."
if ! lsmod | grep -q "^tty0tty"; then
    echo "  Module not loaded, attempting to load..."
    if modprobe tty0tty 2>/dev/null; then
        echo "  Loaded via modprobe (dkms/installed module)."
    else
        KO_PATH=""
        KO_SEARCH_DIRS=()
        if [ -n "$TTY0TTY_DIR" ]; then
            KO_SEARCH_DIRS+=("$TTY0TTY_DIR" "$TTY0TTY_DIR/module")
        fi
        KO_SEARCH_DIRS+=("$TTY0TTY_HOME/module" "$TTY0TTY_HOME")

        for d in "${KO_SEARCH_DIRS[@]}"; do
            if [ -f "$d/tty0tty.ko" ]; then
                KO_PATH="$d/tty0tty.ko"
                break
            fi
        done

        if [ -z "$KO_PATH" ]; then
            KO_PATH=$(find "$HOME" -maxdepth 6 -name "tty0tty.ko" 2>/dev/null | head -n 1)
        fi
        if [ -n "$KO_PATH" ]; then
            echo "  Found module at: $KO_PATH"
            sudo insmod "$KO_PATH" || { echo "  ERROR: insmod failed." >&2; exit 1; }
        else
            INSTALLER="$(dirname "$(readlink -f "$0")")/install-tty0tty.sh"
            if [ -f "$INSTALLER" ]; then
                echo "  Module not found anywhere. Running installer: $INSTALLER"
                bash "$INSTALLER" || { echo "  ERROR: install-tty0tty.sh failed." >&2; exit 1; }
                if ! lsmod | grep -q "^tty0tty"; then
                    echo "  ERROR: installer ran but module still isn't loaded." >&2
                    exit 1
                fi
            else
                echo "  ERROR: tty0tty module not found, and install-tty0tty.sh is not" >&2
                echo "  present next to this script to install it automatically." >&2
                exit 1
            fi
        fi
    fi
else
    echo "  Already loaded."
fi

# ---------------------------------------------------------------------------
# 2. Pick a tty0tty pair
# ---------------------------------------------------------------------------
echo "[2/8] Selecting tty0tty pair..."
if [ -n "$TNT_PAIR" ]; then
    CANDIDATES=("$TNT_PAIR")
else
    CANDIDATES=(0 2 4 6)
fi

TNT_SOCAT_SIDE=""
TNT_WINE_SIDE=""
for n in "${CANDIDATES[@]}"; do
    a="/dev/tnt${n}"
    b="/dev/tnt$((n+1))"
    if [ -e "$a" ] && [ -e "$b" ]; then
        if [ -r "$a" ] && [ -w "$a" ] && [ -r "$b" ] && [ -w "$b" ]; then
            TNT_SOCAT_SIDE="$a"; TNT_WINE_SIDE="$b"; break
        elif [ -z "$TNT_SOCAT_SIDE" ]; then
            TNT_SOCAT_SIDE="$a"; TNT_WINE_SIDE="$b"
        fi
    fi
done

if [ -z "$TNT_SOCAT_SIDE" ] || [ -z "$TNT_WINE_SIDE" ]; then
    echo "  ERROR: no tty0tty device pairs found (expected /dev/tnt0../tnt7)." >&2
    exit 1
fi
echo "  Using pair: ${TNT_SOCAT_SIDE} <-> ${TNT_WINE_SIDE}"

# ---------------------------------------------------------------------------
# 3. Permissions
# ---------------------------------------------------------------------------
echo "[3/8] Checking permissions..."
if [ ! -r "$TNT_SOCAT_SIDE" ] || [ ! -w "$TNT_SOCAT_SIDE" ] || [ ! -r "$TNT_WINE_SIDE" ] || [ ! -w "$TNT_WINE_SIDE" ]; then
    echo "  Current user lacks rw access, falling back to chmod 666."
    echo "  (Permanent fix: sudo usermod -a -G dialout \$USER, then re-login.)"
    sudo chmod 666 "$TNT_SOCAT_SIDE" "$TNT_WINE_SIDE"
else
    echo "  OK."
fi

# ---------------------------------------------------------------------------
# 4. Raw mode on both ends
# ---------------------------------------------------------------------------
echo "[4/8] Setting raw mode..."
stty -F "$TNT_SOCAT_SIDE" raw -echo
stty -F "$TNT_WINE_SIDE" raw -echo

# ---------------------------------------------------------------------------
# 5. Placeholder reader on the Wine-facing end.
#    socat's first write to the pair can block forever if nothing is reading
#    the other side -- no error, no log line, it just hangs.
# ---------------------------------------------------------------------------
echo "[5/8] Starting placeholder reader on ${TNT_WINE_SIDE}..."
cat "$TNT_WINE_SIDE" > /dev/null 2>&1 &
PLACEHOLDER_PID=$!
sleep 0.5
if ! kill -0 "$PLACEHOLDER_PID" 2>/dev/null; then
    echo "  WARNING: placeholder reader exited immediately; continuing anyway." >&2
    PLACEHOLDER_PID=""
fi

cleanup() {
    [ -n "${PLACEHOLDER_PID:-}" ] && kill "$PLACEHOLDER_PID" 2>/dev/null
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 6. (Re)start the socat bridge
# ---------------------------------------------------------------------------
echo "[6/8] (Re)starting socat bridge: ${CONVERTER_IP}:${CONVERTER_PORT} <-> ${TNT_SOCAT_SIDE} ..."
pkill -f "socat.*${CONVERTER_IP}:${CONVERTER_PORT}" 2>/dev/null
sleep 1

nohup socat -d -d -T5 \
    tcp:${CONVERTER_IP}:${CONVERTER_PORT},forever,interval=1,keepalive,keepidle=5,keepintvl=3,keepcnt=3 \
    ${TNT_SOCAT_SIDE},raw,echo=0 \
    > "$SOCAT_LOG" 2>&1 &

SOCAT_PID=$!
sleep 2

if ! kill -0 "$SOCAT_PID" 2>/dev/null; then
    echo "  ERROR: socat exited immediately. Check ${SOCAT_LOG}:" >&2
    tail -n 20 "$SOCAT_LOG" >&2
    exit 1
fi
echo "  socat running (pid ${SOCAT_PID}), logging to ${SOCAT_LOG}"

# ---------------------------------------------------------------------------
# 7. Data flow check (informational)
# ---------------------------------------------------------------------------
echo "[7/8] Checking for data flow (informational, up to 5s)..."
DATA_CONFIRMED=0
for i in $(seq 1 5); do
    if grep -q "write(" "$SOCAT_LOG" 2>/dev/null; then DATA_CONFIRMED=1; break; fi
    sleep 1
done
if [ "$DATA_CONFIRMED" -eq 1 ]; then
    echo "  Confirmed: data is flowing through the bridge."
else
    echo "  NOTE: no data seen in ${SOCAT_LOG} yet after 5s. The ISA500 may be" >&2
    echo "  silent until polled, so this is not necessarily a fault." >&2
fi

# ---------------------------------------------------------------------------
# 8. Register the Wine COM port mapping.
#
#    Wine rebuilds dosdevices/com* on every prefix boot, so the mapping is
#    written to the registry (which wineboot honours) rather than symlinked
#    by hand -- a hand-made symlink gets clobbered by the next boot scan.
# ---------------------------------------------------------------------------
echo "[8/8] Mapping Wine ${WINE_COM_PORT} -> ${TNT_WINE_SIDE} ..."
wine reg add "HKLM\\Software\\Wine\\Ports" /v "$WINE_COM_PORT" /t REG_SZ /d "$TNT_WINE_SIDE" /f >/dev/null
wineserver -k 2>/dev/null; sleep 1
wineboot -u >/dev/null 2>&1

CURRENT_MAPPING=$(wine reg query "HKLM\\Software\\Wine\\Ports" /v "$WINE_COM_PORT" 2>/dev/null | tr -d '\r' | grep REG_SZ | awk '{print $NF}')
if [ "$CURRENT_MAPPING" != "$TNT_WINE_SIDE" ]; then
    echo "  WARNING: registry read-back ('$CURRENT_MAPPING') doesn't match expected ('$TNT_WINE_SIDE')." >&2
else
    echo "  Confirmed: ${WINE_COM_PORT} -> ${TNT_WINE_SIDE}"
fi

# ---------------------------------------------------------------------------
# 9. Launch seaView
# ---------------------------------------------------------------------------
echo "Launching seaView (select ${WINE_COM_PORT} in its port settings)..."
echo "      socat bridge pid ${SOCAT_PID} will keep running in the background;"
echo "      run 'pkill socat' manually when you're done."
echo

wine "$SEAVIEW_EXE"
