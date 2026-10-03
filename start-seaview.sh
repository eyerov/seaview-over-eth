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
SELF="$(readlink -f "$0")"
ACTION=""

DESKTOP_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/applications/seaview-over-eth.desktop"
ICON_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps/seaview-over-eth.png"
LOG_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/seaview-over-eth.log"

# Wine 9.x and earlier crash within seconds of seaView opening a serial port.
# seaView no longer needs one, but it still enumerates them, so the floor stays.
WINE_MIN_MAJOR=10

# Report a fatal error. Launched from a desktop icon there is no terminal to
# print to, so without this a failed check looks like "clicking does nothing".
fail() {
    echo "  ERROR: $1" >&2
    [ -n "${2:-}" ] && echo "$2" >&2
    if [ ! -t 1 ] && command -v zenity >/dev/null 2>&1; then
        zenity --error --no-wrap --title="seaView" \
               --text="<b>seaView could not start</b>\n\n$1\n\n<small>Details: $LOG_FILE</small>" \
               2>/dev/null &
    fi
    exit 1
}

install_desktop_entry() {
    local appdir icon_src tmpdir best
    appdir="$WINEPREFIX/drive_c/Program Files/Impact Subsea/seaView"
    [ -d "$appdir" ] || { echo "ERROR: seaView is not installed in $WINEPREFIX." >&2; exit 1; }

    # Icon: seaView ships a multi-size .ico; take the largest and convert it.
    icon_src="$appdir/seaView.ico"
    mkdir -p "$(dirname "$ICON_FILE")"
    if [ -f "$icon_src" ] && command -v convert >/dev/null 2>&1; then
        tmpdir=$(mktemp -d)
        if convert "$icon_src" "$tmpdir/i_%d.png" 2>/dev/null; then
            best=$(for f in "$tmpdir"/i_*.png; do
                       echo "$(identify -format '%w' "$f" 2>/dev/null || echo 0) $f"
                   done | sort -rn | head -1 | cut -d' ' -f2-)
            [ -n "$best" ] && cp "$best" "$ICON_FILE"
        fi
        rm -rf "$tmpdir"
    fi
    [ -f "$ICON_FILE" ] || echo "  (no icon extracted; the entry will use a generic one)"

    mkdir -p "$(dirname "$DESKTOP_FILE")"
    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=seaView
GenericName=Impact Subsea sonar and altimeter
Comment=Connects to the sensor over Ethernet
Exec=$SELF
Icon=${ICON_FILE:-seaview-over-eth}
Terminal=false
StartupNotify=true
StartupWMClass=seaview.exe
Categories=Science;Engineering;
Keywords=sonar;altimeter;ISA500;subsea;seaview;
EOF
    chmod +x "$DESKTOP_FILE"
    echo "  Menu entry:  $DESKTOP_FILE"

    # The Wine installer leaves entries that launch seaView.exe directly,
    # bypassing every check this script makes. Remove them so there is one
    # obvious way to start the application.
    local removed=0
    for stale in "$HOME/Desktop/seaView.desktop" "$HOME/Desktop/seaView.lnk" \
                 "${XDG_DATA_HOME:-$HOME/.local/share}/applications/wine/Programs/seaView"; do
        if [ -e "$stale" ]; then rm -rf "$stale"; removed=1; fi
    done
    [ "$removed" -eq 1 ] && echo "  Removed the Wine installer's entries (they skipped the startup checks)."

    if [ -d "$HOME/Desktop" ]; then
        cp "$DESKTOP_FILE" "$HOME/Desktop/seaView.desktop"
        chmod +x "$HOME/Desktop/seaView.desktop"
        gio set "$HOME/Desktop/seaView.desktop" metadata::trusted true 2>/dev/null
        echo "  Desktop icon: $HOME/Desktop/seaView.desktop"
    fi

    command -v update-desktop-database >/dev/null 2>&1 && \
        update-desktop-database "${XDG_DATA_HOME:-$HOME/.local/share}/applications" 2>/dev/null
    command -v gtk-update-icon-cache >/dev/null 2>&1 && \
        gtk-update-icon-cache -f -t "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" 2>/dev/null
    echo "  Done. 'seaView' is now in the applications menu."
}

remove_desktop_entry() {
    rm -f "$DESKTOP_FILE" "$ICON_FILE" "$HOME/Desktop/seaView.desktop"
    command -v update-desktop-database >/dev/null 2>&1 && \
        update-desktop-database "${XDG_DATA_HOME:-$HOME/.local/share}/applications" 2>/dev/null
    echo "  Removed."
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --config FILE       Config file (default: ./seaview.conf if present)
  --ip IP             Optional: ping/connect-test a converter before launching
  --port PORT         Port for --ip (default: 23)
  --exe PATH          Windows path to seaView.exe
  --wineprefix PATH   WINEPREFIX to use (default: ~/.wine-seaview)
  --install-desktop-entry   Add a "seaView" icon to the applications menu
                            and the desktop, then exit
  --remove-desktop-entry    Remove them again, then exit
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
        --install-desktop-entry) ACTION=install_desktop ;  shift ;;
        --remove-desktop-entry)  ACTION=remove_desktop  ;  shift ;;
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

case "$ACTION" in
    install_desktop) install_desktop_entry; exit 0 ;;
    remove_desktop)  remove_desktop_entry;  exit 0 ;;
esac

# No terminal (launched from the icon)? Keep a log, so a failure is diagnosable.
if [ ! -t 1 ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    exec >>"$LOG_FILE" 2>&1
    echo "=== $(date "+%Y-%m-%d %H:%M:%S") launched from desktop entry ==="
fi

# ---------------------------------------------------------------------------
# [1/4] Wine present and new enough
# ---------------------------------------------------------------------------
echo "[1/4] Checking Wine..."
if ! command -v wine >/dev/null 2>&1; then
    fail "Wine is not installed." "See SETUP-GUIDE.md Part 3."
fi
WINE_VER_RAW="$(wine --version 2>/dev/null | head -1)"
WINE_MAJOR="$(printf '%s' "$WINE_VER_RAW" | sed -n 's/^wine-\([0-9]\{1,\}\).*/\1/p')"
if [ -z "$WINE_MAJOR" ]; then
    echo "  WARNING: could not parse Wine version from '$WINE_VER_RAW'; continuing." >&2
elif [ "$WINE_MAJOR" -lt "$WINE_MIN_MAJOR" ]; then
    fail "Wine $WINE_VER_RAW is too old; seaView needs ${WINE_MIN_MAJOR}.0 or newer." \
         "Ubuntu's own package is 9.0. Install WineHQ's build -- SETUP-GUIDE.md Part 3."
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
        fail "The Wine environment is 32-bit, but seaView is 64-bit." \
             "Recreate it -- see SETUP-GUIDE.md Part 4."
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

cd "$WINEPREFIX/drive_c/Program Files/Impact Subsea/seaView" 2>/dev/null \
    || fail "seaView is not installed in this Wine environment." "See SETUP-GUIDE.md Part 5."
exec wine seaView.exe "$@"
