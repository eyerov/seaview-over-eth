# seaview-over-eth

Runs **Impact Subsea seaView** on Linux under Wine, with the sonar/altimeter
reached over an RS485-to-Ethernet converter.

Everything needed is in this folder — installer, scripts and guides. There is
no USB dependency and nothing to fetch from elsewhere.

> Setting this up on an operator machine? Use
> [SETUP-GUIDE.md](SETUP-GUIDE.md) instead — this README is the technical
> reference.
>
> Deciding whether to adopt this architecture, or porting it to another
> application? See [STUDY-REPORT.md](STUDY-REPORT.md).

This follows the same architecture as
[serial-over-eth](https://github.com/eyerov/serial-over-eth) (NOR-CP-Logger),
with four seaView-specific differences documented under
[Differences from serial-over-eth](#differences-from-serial-over-eth).

The data path for the FMD deployment is:

```
ISA500 / sonar head
    |  RS485
    v
RS485-to-Ethernet converter        (e.g. 192.168.2.125:2000)
    |  TCP
    v
socat                              (bridge)
    |
    v
/dev/tnt2  <-- tty0tty -->  /dev/tnt3     (virtual null-modem pair)
                                 |
                                 v
                            Wine COM11
                                 |
                                 v
                            seaView.exe
```

`tty0tty` is a kernel module providing four pairs of interconnected virtual
serial ports (`/dev/tnt0`..`/dev/tnt7`). `socat` writes converter traffic
into one end of a pair; Wine reads the other end as a COM port.

`TRANSPORT="loopback"` brings up the identical port path with no converter
behind it, so the whole stack can be validated with no hardware at all — no
converter and no USB adapter. There is deliberately **no USB transport**:
everything needed is in this folder.

## Contents

| File | Purpose |
|---|---|
| [start-seaview.sh](start-seaview.sh) | Sets up the bridge and launches seaView |
| [install-tty0tty.sh](install-tty0tty.sh) | Installs/builds the tty0tty kernel module |
| [seaview.conf.example](seaview.conf.example) | Template for your local config |
| [SETUP-GUIDE.md](SETUP-GUIDE.md) | Step-by-step guide for operator machines |
| [STUDY-REPORT.md](STUDY-REPORT.md) | Architecture analysis and implementation plan |
| `tty0tty/` | Upstream module source (git-ignored) |

The seaView installer is **not** committed — it is ~80 MB, past the point
where git is a sensible home for it. Keep `Seaview (Rev 3.1.8.2).exe` in the
working folder (copy it from the IMPACT drive after a fresh clone) and see
[Step 3](#step-3--install-seaview).

---

## Prerequisites

| Requirement | Why | Install |
|---|---|---|
| **Wine ≥ 10** | 9.x crashes on serial I/O — see below | WineHQ repo, see Step 1 |
| `socat` | the TCP-to-serial bridge | `sudo apt install socat` |
| `build-essential` | compiles the kernel module | `sudo apt install build-essential` |
| `linux-headers-$(uname -r)` | kernel headers to build against | `sudo apt install linux-headers-$(uname -r)` |
| sudo rights | loading a kernel module needs root | |

seaView is a Qt/C++ application, so unlike NOR-CP-Logger it does **not**
need Wine Mono. Skip that step if you are porting from the CP Logger setup.

### Wine version requirement

**Wine 9 and earlier cannot run seaView at all.** A few seconds after
seaView opens a serial port the process dies with:

```
Unhandled exception: page fault on read access to 0x0000000000000000
ntdll.so+0x35a0b:  mov (%rdi),%rdi
```

Wine ≤ 9 implements `WaitCommEvent` by spawning a worker thread per wait
(`dlls/ntdll/unix/serial.c`); that thread can start with a null argument and
faults on its first dereference. Wine 10 replaced the whole path with the
Wine server's async I/O and the crashing function no longer exists.

Ubuntu 24.04 ships Wine 9.0, so the distro package will not do. `start-seaview.sh`
refuses to launch on anything older than 10 rather than let it fail confusingly.

### The prefix must be 64-bit

`seaView.exe` is a PE32+ x86-64 binary. The **installer** is 32-bit and runs
happily in a `win32` prefix — leaving behind an application that can never
start, failing with `Bad EXE format`. Stock `~/.wine` on Ubuntu is `win32`,
which is why this setup keeps its own prefix at `~/.wine-seaview`.

---

## Step 1 — Install Wine 10+

```bash
sudo mkdir -pm755 /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
sudo wget -NP /etc/apt/sources.list.d/ \
    https://dl.winehq.org/wine-builds/ubuntu/dists/$(lsb_release -cs)/winehq-$(lsb_release -cs).sources
sudo apt update
sudo apt install --install-recommends winehq-stable
wine --version        # must be 10.x or newer
```

---

## Step 2 — Create the 64-bit prefix

```bash
WINEARCH=win64 WINEPREFIX="$HOME/.wine-seaview" \
    WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -u
head -5 ~/.wine-seaview/system.reg | grep arch     # expect #arch=win64
```

`start-seaview.sh` creates this for you if it is missing, and refuses to run
against a 32-bit prefix.

---

## Step 3 — Install seaView

```bash
WINEPREFIX="$HOME/.wine-seaview" wine "Seaview (Rev 3.1.8.2).exe"
```

A Qt Installer Framework wizard; accept the defaults. Confirm the path:

```bash
find ~/.wine-seaview/drive_c -name 'seaView.exe' -exec winepath -w {} \;
```

The deployment is self-contained (all Qt 6 DLLs ship beside the exe), so an
existing good install can simply be copied between prefixes instead of
re-running the wizard.

---

## Step 4 — Install the tty0tty module

Only needed for `TRANSPORT="ethernet"`.

```bash
./install-tty0tty.sh
lsmod | grep tty0tty
ls -l /dev/tnt*          # expect /dev/tnt0 .. /dev/tnt7
```

This script is taken unchanged from `serial-over-eth`; its behaviour, the
four install methods it tries, and the broken piduino.org apt repo warning
all apply here identically.

Then log out and back in — the installer adds you to `dialout`, and group
changes do not affect a running session.

---

## Step 5 — Configure

```bash
cp seaview.conf.example seaview.conf
```

Set `CONVERTER_IP` and `CONVERTER_PORT` to match your converter. Everything
else has a working default.

| Setting | Default | Notes |
|---|---|---|
| `TRANSPORT` | `ethernet` | or `loopback` to validate with no hardware |
| `CONVERTER_PORT` | `2000` | must be the **raw data** port, not the admin menu |
| `TNT_PAIR` | auto-detect | `0`, `2`, `4`, or `6`; pairs are N ↔ N+1 |
| `WINE_COM_PORT` | `COM11` | what you select inside seaView |
| `WINEPREFIX` | `~/.wine-seaview` | must be 64-bit |

---

## Step 6 — Run

```bash
./start-seaview.sh
```

Then select **COM11** in seaView's port settings.

```bash
./start-seaview.sh --ip 192.168.2.99 --port 4001 --com COM3
./start-seaview.sh --transport loopback --feed   # no hardware at all
./start-seaview.sh --help
```

Precedence: built-in defaults → config file → command-line flags →
auto-detection for anything still unset.

### Shutting down

The socat bridge is deliberately left running when seaView exits, so closing
the app does not drop the link:

```bash
pkill socat
```

---

## Baud rate over the bridge

**On the ethernet transport, the baud rate you select in seaView does
nothing.** It configures a virtual tty that has no UART behind it. The real
serial parameters — 115200 8N1 for a default ISA500 — live in the
**converter's own configuration**, and must be set there.

This is the most common cause of "the port opens but the data is garbage":
Wine faithfully applies a baud rate to a virtual port, and the converter is
talking at a different one.

The same is true on the loopback transport: the tty0tty pair accepts any baud
setting and ignores it.

---

## One port, by design

seaView opens and polls **every COM port Wine advertises**, continuously, on
its GUI thread. The intended end state on the FMD machine is therefore exactly
one port: **COM11 and nothing else.**

That is achievable because of how Wine discovers ports. Its boot scan looks at
precisely three patterns:

```
/dev/ttyS*    /dev/ttyUSB*    /dev/ttyACM*
```

`/dev/tnt*` is **not** among them. A tty0tty device can only become a COM port
by being named in `HKLM\Software\Wine\Ports` — which is exactly what step 8
does. So the bridge contributes one port and one only.

Everything Wine auto-detects is an *extra* port seaView will poll. On a machine
with no serial hardware the kernel still creates 32 `/dev/ttyS*` nodes, and
Wine turns each into a COM port:

| Source | Ports | With `8250.nr_uarts=0` |
|---|---|---|
| `/dev/ttyS*` | 32 | **0** |
| `/dev/ttyUSB*` | 0 (no USB in this architecture) | **0** |
| `/dev/tnt*` via Ports key | 1 | **1** |
| **Total seaView sees** | **33** | **1** |

Measured at 33–34 ports, the scan saturates the GUI thread:

| Serial devices | seaView GUI thread | Frame rate |
|---|---|---|
| 34 | ~100% of one core | 12 frames / 20 s |
| 64 (test) | saturated, 2.5× the error callbacks | — |

**There is no way to restrict this from inside Wine.** Tested on Wine 11: a
prefix with every `dosdevices/com*` symlink deleted and only COM11 in the
Ports key still came back with 33 devices after boot — the Ports key *adds*
ports, it never limits them. The only lever is what exists in `/dev`.

So the fix is kernel-side. Confirm the onboard ports are phantom first:

```bash
cat /sys/class/tty/ttyS0/type      # 0 = PORT_UNKNOWN, no real UART
```

Then remove them via the kernel command line:

```bash
sudo sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 8250.nr_uarts=0"/' /etc/default/grub
sudo update-grub && sudo reboot
```

Use `8250.nr_uarts=1` instead if `0` is rejected; that leaves one harmless
`ttyS0`, so seaView sees two ports rather than one — still about a
seventeenth of the original load.

`start-seaview.sh` reports the count at every launch, and says
`COM11 only (as designed)` once it is right.

This affects CP Logger too, and in its favour: its COM10 also comes from the
Ports key over a tty0tty device, so neither application depends on
`/dev/ttyS*` existing.

---

## Verifying the bridge

```bash
tail -f /tmp/socat-seaview.log        # "write(" lines mean data is arriving
cat /dev/tnt3                          # read the raw stream without Wine
wine reg query "HKLM\Software\Wine\Ports" /v COM11
```

To test the converter with nothing else in the path:

```bash
socat - tcp:192.168.2.125:2000
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Bad EXE format` | 32-bit prefix | Recreate as `WINEARCH=win64` (Step 2) |
| Dies ~10 s after start, `page fault ... 0x0` | Wine ≤ 9 | Install Wine 10+ (Step 1) |
| UI very sluggish, < 1 fps | Wine is exposing more than just COM11 | See [One port, by design](#one-port-by-design) |
| Port opens, data is garbage | Converter baud ≠ device baud | Set it in the converter, not seaView |
| `COM11` missing from seaView's list | Mapping written after seaView started | Re-run `./start-seaview.sh`, wait for step `[8/8]` |
| No data in seaView | Wrong converter IP/port | `socat - tcp:<ip>:<port>`; check raw vs admin port |
| `socat` exits immediately | Another socat holds the port | `pkill socat`, retry |
| Everything hangs, no output | socat's first write blocked | Confirm the step-5 placeholder reader started |
| `/dev/tnt*` root-only | udev rule missing, or no re-login | See `serial-over-eth` README, Step 3 |
| Module fails to build | Missing kernel headers | `sudo apt install build-essential linux-headers-$(uname -r)` |

---

## Running alongside CP Logger on the same machine

Both applications are deployed together on the FMD machine. They coexist
cleanly, but the split matters:

| | CP Logger | seaView |
|---|---|---|
| Wine prefix | `~/.wine` (**win32**) | `~/.wine-seaview` (**win64**) |
| Runtime | .NET — needs Wine Mono | Qt/C++ — no Mono |
| COM port | `COM10` | `COM11` |
| tty0tty pair | e.g. `/dev/tnt2` ↔ `/dev/tnt3` | a **different** pair, e.g. `/dev/tnt4` ↔ `/dev/tnt5` |
| socat bridge | its own | its own |

The Wine **binary** is shared system-wide; the **prefixes** are independent.
One Wine 11 install serves both — `serial-over-eth`'s own README records Wine
Mono 9.4.0 as "the version verified against `wine-11.0`", so both stacks
target the same Wine.

`HKLM\Software\Wine\Ports` lives inside each prefix, so COM10 and COM11
would not actually collide even if both used the same number. Distinct
numbers are for operator clarity, and so a port name unambiguously identifies
which application it belongs to.

**If both run at once**, give each its own tty0tty pair — `TNT_PAIR` in
`seaview.conf`, set to something the CP Logger config does not use. Each
application gets its own socat bridge to its own converter. Note that
`pkill socat` stops **both**; kill by pid or by match instead:

```bash
pkill -f "socat.*<seaview-converter-ip>"
```

---

## Differences from serial-over-eth

Four things change when the Windows application is seaView rather than
NOR-CP-Logger. Full reasoning in [STUDY-REPORT.md](STUDY-REPORT.md).

| | serial-over-eth (CP Logger) | seaview-over-eth |
|---|---|---|
| **Wine prefix** | 32-bit, stock `~/.wine` | **64-bit**, `~/.wine-seaview` |
| **Runtime** | .NET — needs Wine Mono | Qt/C++ — **no Mono** |
| **Wine version** | 11 in practice | **≥ 10 enforced**, 9 is fatal |
| **Port selection** | operator picks a port | **scans every port** — phantom ports must be cut |

Everything else — socat, tty0tty, the `HKLM\Software\Wine\Ports` mapping,
the config/flag precedence, the placeholder-reader workaround, and
`install-tty0tty.sh` itself — carries over unchanged.

---

## Known issues

Inherited from the reference architecture:

- **The tty0tty module does not survive a reboot** when built with `make` +
  `insmod`. `start-seaview.sh` step 1 reloads it from the staged copy.
- **Kernel upgrades break the built module.** Re-run `./install-tty0tty.sh`.
  Registering it with DKMS would automate this; not wired up yet.
- **Upstream tty0tty documents testing up to kernel 6.12.x.** Newer kernels
  may need a source update before it compiles.

seaView-specific:

- **Modem control lines do not cross the bridge.** DTR/RTS asserted by Wine
  on a `tnt` device do not reach the converter's RS485 side. Line-powered
  RS485/RS232 converters that rely on handshake power will not work on the
  ethernet transport — power them properly instead.
- **RS485 turnaround timing is the converter's problem.** Half-duplex
  direction control happens inside the converter; TCP adds latency and
  jitter that a tightly-timed polling protocol may not tolerate. See the
  study report's risk register.
