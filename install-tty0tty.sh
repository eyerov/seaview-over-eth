#!/bin/bash
#
# install-tty0tty.sh
#
# Installs the tty0tty virtual null-modem kernel module, trying several
# methods in order so this works across machines with varying levels of
# internet access / installed tooling:
#
#   1. Already installed?              -> skip
#   2. Bundled source next to this
#      script (offline-friendly)?      -> stage + build + install from it
#   3. dkms package from piduino.org
#      apt repo (needs internet)?      -> apt install tty0tty-dkms
#   4. Download zip from GitHub
#      (needs internet + wget/curl
#      + unzip, but NOT git)?          -> stage + build + install from it
#
# Whichever source method is used, the source tree is first staged into a
# fixed, per-user location:
#
#   ${XDG_DATA_HOME:-$HOME/.local/share}/tty0tty
#
# so the built module always ends up at a predictable path
# (<install-dir>/module/tty0tty.ko). That means cp-logger.conf can just use
# the default TTY0TTY_DIR instead of a machine-specific path.
#
# Also sets up the udev rule (via `make install`) and adds the current
# user to the `dialout` group so /dev/tnt* is usable without sudo/chmod.
#
# Usage: ./install-tty0tty.sh [--bundle-dir DIR] [--install-dir DIR]
#
#   --bundle-dir DIR   Path to a pre-downloaded tty0tty source tree
#                      (containing a module/ subdir). Defaults to looking
#                      for ./tty0tty-master or ./tty0tty next to this script.
#   --install-dir DIR  Where to stage + build the source tree.
#                      Default: ${XDG_DATA_HOME:-$HOME/.local/share}/tty0tty

set -u

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
BUNDLE_DIR=""
GITHUB_ZIP_URL="https://github.com/lcgamboa/tty0tty/archive/refs/heads/master.zip"

# Fixed, per-user home for the tty0tty source tree + built module.
# Keep this in sync with the TTY0TTY_DIR default in start-cp-logger.sh.
INSTALL_DIR="${TTY0TTY_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/tty0tty}"

# ---------------------------------------------------------------------------
# Parse args
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --bundle-dir)  BUNDLE_DIR="$2"; shift 2 ;;
        --install-dir) INSTALL_DIR="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $(basename "$0") [--bundle-dir DIR] [--install-dir DIR]"
            echo "  --install-dir defaults to \${XDG_DATA_HOME:-\$HOME/.local/share}/tty0tty"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

echo "=== tty0tty installer ==="
echo "Install dir: $INSTALL_DIR"

# ---------------------------------------------------------------------------
# Step 1: already installed / already loaded?
# ---------------------------------------------------------------------------
if lsmod | grep -q "^tty0tty"; then
    echo "[OK] tty0tty module is already loaded. Nothing to do."
    exit 0
fi

if modinfo tty0tty >/dev/null 2>&1; then
    echo "[OK] tty0tty module is installed (known to modinfo) but not loaded."
    echo "     Loading it now..."
    sudo modprobe tty0tty && {
        echo "[OK] Loaded via modprobe."
        exit 0
    }
    echo "[WARN] modprobe failed even though modinfo found it. Continuing to reinstall..."
fi

# ---------------------------------------------------------------------------
# Helper: build + install from a source tree containing module/
# ---------------------------------------------------------------------------
build_and_install_from() {
    local src_dir="$1"
    if [ ! -d "$src_dir/module" ]; then
        echo "[ERROR] '$src_dir' does not contain a module/ directory." >&2
        return 1
    fi

    echo "  Building from: $src_dir/module"
    if ! command -v make >/dev/null 2>&1; then
        echo "  'make' not found, attempting to install build tools..." >&2
        sudo apt-get update -y && sudo apt-get install -y build-essential linux-headers-"$(uname -r)" || {
            echo "[ERROR] Failed to install build tools automatically." >&2
            echo "         Install manually: sudo apt-get install build-essential linux-headers-\$(uname -r)" >&2
            return 1
        }
    fi

    (
        cd "$src_dir/module" || exit 1
        make && sudo make install
    ) || {
        echo "[ERROR] Build or install failed in $src_dir/module" >&2
        return 1
    }

    echo "[OK] Built and installed from $src_dir"
    return 0
}

# ---------------------------------------------------------------------------
# Helper: copy a source tree into INSTALL_DIR so the built module always
# lands at a predictable path. Echoes the staged path on success.
# ---------------------------------------------------------------------------
stage_source() {
    local src_dir="$1"

    # Already sitting in the install dir? Nothing to copy.
    if [ "$(readlink -f "$src_dir")" = "$(readlink -f "$INSTALL_DIR")" ]; then
        echo "  Source is already at $INSTALL_DIR, building in place." >&2
        return 0
    fi

    echo "  Staging source into $INSTALL_DIR ..." >&2
    mkdir -p "$INSTALL_DIR" || {
        echo "[ERROR] Could not create $INSTALL_DIR" >&2
        return 1
    }

    # Wipe any previous staged tree so a stale build can't shadow the new one.
    rm -rf "${INSTALL_DIR:?}"/* 2>/dev/null

    cp -a "$src_dir"/. "$INSTALL_DIR"/ || {
        echo "[ERROR] Failed to copy $src_dir into $INSTALL_DIR" >&2
        return 1
    }

    # Drop any object files carried over from a build on another machine /
    # kernel, so `make` rebuilds cleanly against this kernel's headers.
    ( cd "$INSTALL_DIR/module" && make clean >/dev/null 2>&1 )

    return 0
}

# ---------------------------------------------------------------------------
# Step 2: bundled source next to this script (fully offline path)
# ---------------------------------------------------------------------------
if [ -z "$BUNDLE_DIR" ]; then
    for candidate in "$SCRIPT_DIR/tty0tty-master" "$SCRIPT_DIR/tty0tty"; do
        if [ -d "$candidate/module" ]; then
            BUNDLE_DIR="$candidate"
            break
        fi
    done
fi

if [ -n "$BUNDLE_DIR" ] && [ -d "$BUNDLE_DIR/module" ]; then
    echo "[2] Found bundled source at $BUNDLE_DIR, using it (no network needed)..."
    if stage_source "$BUNDLE_DIR" && build_and_install_from "$INSTALL_DIR"; then
        sudo modprobe tty0tty || sudo insmod "$INSTALL_DIR/module/tty0tty.ko"
        echo "[OK] Installed from bundled source (staged at $INSTALL_DIR)."
        # fall through to group setup below
    else
        echo "[WARN] Bundled source found but staging/build/install failed. Will try other methods." >&2
        BUNDLE_DIR=""
    fi
fi

# ---------------------------------------------------------------------------
# Step 3: dkms package via piduino.org apt repo (needs internet, no git needed)
# ---------------------------------------------------------------------------
if ! lsmod | grep -q "^tty0tty" && ! modinfo tty0tty >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1 && ping -c 1 -W 2 www.piduino.org >/dev/null 2>&1; then
        echo "[3] Trying prebuilt dkms package from piduino.org..."
        wget -q -O- http://www.piduino.org/piduino-key.asc | sudo gpg --dearmor --yes --output /usr/share/keyrings/piduino-archive-keyring.gpg \
            && echo "deb [signed-by=/usr/share/keyrings/piduino-archive-keyring.gpg] http://apt.piduino.org $(lsb_release -c -s) piduino" | sudo tee /etc/apt/sources.list.d/piduino.list >/dev/null \
            && sudo apt update -y \
            && sudo apt install -y tty0tty-dkms

        if lsmod | grep -q "^tty0tty" || modinfo tty0tty >/dev/null 2>&1; then
            sudo modprobe tty0tty
            echo "[OK] Installed via piduino apt repo."
        else
            echo "[WARN] piduino apt install did not result in a usable module. Trying next method." >&2
        fi
    else
        echo "[3] Skipping piduino apt method (apt-get unavailable or no network route to piduino.org)."
    fi
fi

# ---------------------------------------------------------------------------
# Step 4: download zip from GitHub directly (needs internet + wget/curl + unzip)
# ---------------------------------------------------------------------------
if ! lsmod | grep -q "^tty0tty" && ! modinfo tty0tty >/dev/null 2>&1; then
    echo "[4] Trying to download source zip from GitHub (no git required)..."

    if ! command -v unzip >/dev/null 2>&1; then
        echo "  'unzip' not found, attempting to install it..."
        sudo apt-get update -y && sudo apt-get install -y unzip
    fi

    TMP_DIR=$(mktemp -d)
    ZIP_PATH="$TMP_DIR/tty0tty.zip"

    if command -v wget >/dev/null 2>&1; then
        wget -q -O "$ZIP_PATH" "$GITHUB_ZIP_URL"
    elif command -v curl >/dev/null 2>&1; then
        curl -sL -o "$ZIP_PATH" "$GITHUB_ZIP_URL"
    else
        echo "[ERROR] Neither wget nor curl is available; cannot download." >&2
    fi

    if [ -f "$ZIP_PATH" ] && [ -s "$ZIP_PATH" ]; then
        unzip -q "$ZIP_PATH" -d "$TMP_DIR"
        EXTRACTED_DIR=$(find "$TMP_DIR" -maxdepth 1 -type d -name "tty0tty-*" | head -n 1)
        if [ -n "$EXTRACTED_DIR" ]; then
            stage_source "$EXTRACTED_DIR" && build_and_install_from "$INSTALL_DIR" && {
                sudo modprobe tty0tty || sudo insmod "$INSTALL_DIR/module/tty0tty.ko"
                echo "[OK] Installed from downloaded GitHub archive (staged at $INSTALL_DIR)."
            }
        else
            echo "[ERROR] Could not find extracted tty0tty directory after unzip." >&2
        fi
    else
        echo "[ERROR] Download failed or produced an empty file." >&2
    fi

    rm -rf "$TMP_DIR"
fi

# ---------------------------------------------------------------------------
# Final check
# ---------------------------------------------------------------------------
if ! lsmod | grep -q "^tty0tty"; then
    echo
    echo "[FAILED] Could not install/load tty0tty by any method." >&2
    echo "  Options:" >&2
    echo "   - Manually place a tty0tty source tree (with a module/ subdir)" >&2
    echo "     next to this script, named 'tty0tty-master' or 'tty0tty', and re-run." >&2
    echo "   - Or run: sudo apt-get install build-essential linux-headers-\$(uname -r)" >&2
    echo "     and retry, in case the build failed due to missing kernel headers." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Group setup so /dev/tnt* is usable without sudo/chmod
# ---------------------------------------------------------------------------
echo
echo "=== Post-install: user permissions ==="
if id -nG "$USER" | grep -qw dialout; then
    echo "[OK] $USER is already in the 'dialout' group."
else
    echo "Adding $USER to the 'dialout' group (required for /dev/tnt* access)..."
    sudo usermod -a -G dialout "$USER"
    echo "[ACTION REQUIRED] Log out and back in (or reboot) for group membership to take effect."
fi

echo
echo "=== Done ==="
ls -l /dev/tnt* 2>/dev/null
echo
if [ -f "$INSTALL_DIR/module/tty0tty.ko" ]; then
    echo "Module source + build staged at: $INSTALL_DIR"
    echo "  (start-cp-logger.sh looks here by default, so TTY0TTY_DIR can be left"
    echo "   blank in cp-logger.conf. To be explicit, set:"
    echo "   TTY0TTY_DIR=\"$INSTALL_DIR/module\")"
    echo
fi
echo "tty0tty is installed and loaded. You can now run start-cp-logger.sh."
