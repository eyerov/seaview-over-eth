# seaView — Setup Guide

**For Ubuntu 24.04**

Sets up seaView on a new machine. Parts 1–7 are one-time setup; after that, use
the [Everyday use](#everyday-use) section. Allow about 20 minutes.

---

## Before you start

- Ubuntu 24.04
- This folder, including the installer `Seaview (Rev 3.1.8.2).exe`
- The administrator password for the machine
- The converter's **IP address** (e.g. `192.168.2.181`) and its **port**
  (often `23`) — you put these in `seaview.conf` in Part 7
- The converter powered on, wired to the sensor, and on the same network
- An internet connection, to install Wine

---

## Part 1 — Open the folder

```bash
cd ~/seaview-over-eth
```

Confirm you are in the right place:

```bash
ls
```

You should see `start-seaview.sh` and the `.exe` installer.

---

## Part 2 — Make the script executable

```bash
chmod +x start-seaview.sh
```

No output means it worked.

---

## Part 3 — Install Wine

**seaView needs Wine 10 or newer.** Ubuntu's own Wine package is version 9,
which cannot run seaView reliably. Install WineHQ's version instead:

```bash
sudo mkdir -pm755 /etc/apt/keyrings
```

```bash
sudo wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
```

```bash
sudo wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources
```

```bash
sudo apt update && sudo apt install --install-recommends winehq-stable
```

This downloads several hundred megabytes and takes a few minutes.

```bash
wine --version
```

You should see **`wine-10.0` or higher**. If it prints `wine-9.0`, the steps
above did not take effect — run them again before continuing.

---

## Part 4 — Create the Wine environment

seaView is a 64-bit program and needs a 64-bit Wine environment. The default
one on Ubuntu is 32-bit, which will not work.

```bash
WINEARCH=win64 WINEPREFIX="$HOME/.wine-seaview" WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -u
```

The first Wine command on a new machine takes a minute or two. Wait for it to
return you to the prompt.

```bash
head -5 ~/.wine-seaview/system.reg | grep arch
```

This must print `#arch=win64`. If it prints `#arch=win32`, delete the folder
with `rm -rf ~/.wine-seaview` and run the command again.

---

## Part 5 — Install seaView

```bash
cd ~/seaview-over-eth
WINEPREFIX="$HOME/.wine-seaview" wine "Seaview (Rev 3.1.8.2).exe"
```

The installer window opens. Work through it and **accept the default options**,
including the default install location.

> **Installing on several machines?** The installer also runs without the
> wizard:
>
> ```bash
> WINEPREFIX="$HOME/.wine-seaview" wine "Seaview (Rev 3.1.8.2).exe" install \
>     --root 'C:\Program Files\Impact Subsea\seaView' \
>     --accept-licenses --default-answer --confirm-command
> ```

Confirm where it landed:

```bash
WINEPREFIX="$HOME/.wine-seaview" find ~/.wine-seaview/drive_c -name 'seaView.exe' -exec winepath -w {} \;
```

This should print:

```
C:\Program Files\Impact Subsea\seaView\seaView.exe
```

If nothing is printed, the installation did not complete; run it again.

---

## Part 6 — Speed up the display

Skip this only if the machine has a real serial port on its motherboard — most
laptops and mini-PCs do not.

Linux pretends to have 32 serial ports even when none exist. seaView checks
every one of them, over and over, which makes its display slow and jerky. This
happens even though seaView reaches the sensor over the network and uses none
of those ports.

First confirm the ports are imaginary:

```bash
cat /sys/class/tty/ttyS0/type
```

If this prints **`0`**, they are safe to remove — continue. If it prints
anything else, the machine has real serial hardware; skip to Part 7 and mention
it if you report any slowness.

```bash
sudo sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 8250.nr_uarts=0"/' /etc/default/grub
```

```bash
sudo update-grub
```

Then **reboot**.

After rebooting:

```bash
ls /dev/ttyS* 2>/dev/null | wc -l
```

This should print **`0`**. If it still prints `32`, see
[Troubleshooting](#troubleshooting).

> If `0` causes any problem on this machine, use `8250.nr_uarts=1` instead and
> repeat. That leaves one harmless port.

---

## Part 7 — Configure and start seaView

Put the converter's address in the configuration file:

```bash
cd ~/seaview-over-eth
gnome-text-editor seaview.conf
```

```
CONVERTER_IP="192.168.2.181"
CONVERTER_PORT="23"
```

Change only the text inside the quotation marks, and keep them. Save with
**Ctrl + S** and close the editor.

Then start it:

```bash
./start-seaview.sh
```

The script runs five checks and opens seaView. You should see:

```
[4/5] Checking the converter...
  192.168.2.181:23 reachable, accepting connections.
[5/5] Pre-filling seaView's device search...
  Search will open on NETWORK, 192.168.2.181:23.
```

In seaView, the **Devices** panel opens with its search already pointed at the
network and your converter's address filled in. Press **Search**.

The sensor appears as a card — model, serial number, firmware, and the
connection it was found on, e.g. `SOL: 192.168.2.181:23 (RS485 9600)`.

From there, add the app you need (**FMD**, **Altimeter**, **AHRS** …) from the
list on the left.

> **If the search finds nothing**, add the port by hand instead: in the
> **Comms** panel click **+**, choose **Add a Serial Over Lan Port**, and enter
> your converter's IP and port with **Protocol** `TCP` and **Encoding** `Raw`.

---

## Everyday use

```bash
cd ~/seaview-over-eth
./start-seaview.sh
```

The search opens pre-filled each time, so connecting is one press of
**Search** in the Devices panel.

Parts 1–7 do not need repeating.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| seaView closes by itself shortly after starting | Wine is too old. `wine --version` must be 10 or higher. Redo Part 3. |
| `Bad EXE format` | The Wine environment is 32-bit. Redo Part 4. |
| seaView is slow and jerky | Part 6 was skipped or did not apply. Check `ls /dev/ttyS* 2>/dev/null \| wc -l` — it should be `0`. |
| `No Devices Detected` after pressing Search | Check `CONVERTER_IP` and `CONVERTER_PORT` in `seaview.conf`, and that step `[4/5]` reported the converter reachable. |
| `WARNING: ... does not respond to ping` | The converter is off, or its network cable is unplugged. Check the link light on the adapter. |
| The Serial Over LAN port will not open | The converter is unreachable, or something else is holding its single session. `ping` it, and close any other software talking to it. |
| Device found but readings look wrong | The converter's own serial settings do not match the sensor. seaView shows what it negotiated, e.g. `(RS485 9600)` — compare with the converter's web page. |
| `Permission denied` running the script | Part 2 was skipped. |
| `wine: command not found` | Run Part 3. |
| Still 32 ports after Part 6 | The GRUB edit did not apply. Check `/etc/default/grub` contains `8250.nr_uarts=0`, re-run `sudo update-grub`, reboot. |

### Reporting a problem

Include the output of:

```bash
wine --version
```

```bash
./start-seaview.sh 2>&1 | head -20
```

plus a screenshot of the Comms panel.

---

## Quick reference

| Task | Command |
|---|---|
| Go to the folder | `cd ~/seaview-over-eth` |
| Start seaView | `./start-seaview.sh` |
| Edit settings | `gnome-text-editor seaview.conf` |
| Connect to the sensor | Comms → **+** → Add a Serial Over Lan Port |
| Find the sensor | Devices → **🔍** |

---

# Technical reference

Everything above is the procedure. This section is the reasoning — read it when
something does not behave, or before changing the setup.

## Why Wine 10 or newer

Wine 9 and earlier implement `WaitCommEvent` by spawning a worker thread per
wait (`dlls/ntdll/unix/serial.c`). That thread can start with a null argument
and faults on its first dereference:

```
Unhandled exception: page fault on read access to 0x0000000000000000
ntdll.so+0x35a0b:  mov (%rdi),%rdi
```

seaView died 6–9 seconds after opening a serial port. Wine 10 replaced the
whole path with the Wine server's async I/O and the crashing function no longer
exists.

seaView no longer opens a serial port in this architecture, so the bug is
unlikely to fire — but it still *enumerates* ports, and there is no benefit to
running an older Wine. The floor stays at 10.

## Why the Wine environment must be 64-bit

`seaView.exe` is a 64-bit binary. The **installer** is 32-bit and runs happily
in a 32-bit environment — leaving behind an application that can never start,
failing with `Bad EXE format`. Nothing about the installation reports a
problem; the failure only appears at launch.

## Phantom serial ports

seaView opens and polls **every COM port Windows offers it**, continuously, on
the thread that draws its display. It does this regardless of how it reaches
the sensor, so it matters even though nothing here uses a serial port.

On a machine with no serial hardware the kernel still creates 32 `/dev/ttyS*`
nodes, and Wine turns each into a COM port. Measured on this machine:

| | Before Part 6 | After |
|---|---|---|
| Serial ports Wine exposes | 32 | **0** |
| Display thread CPU | 97.2% | **0.2%** |
| Frame rate | 0.6 fps | **~10 fps** |

Wine cannot be told to expose fewer ports — its registry key *adds* ports and
never limits them, so the only lever is what exists in `/dev`. Hence the kernel
command line.

## Converter settings

The converter's serial side must match the sensor. seaView reports what it
found, e.g. `SOL: 192.168.2.181:23 (RS485 9600)`, which is a useful check
against the converter's own web page.

Relevant settings on a typical unit:

- **Baud / data / parity / stop** — must match the sensor. An ISA500 defaults
  to **RS485, 9600, N81**.
- **Work mode** — TCP Server, with the port seaView connects to.
- **UART packet time** — low (1 ms) is good practice; it was not what fixed
  discovery here, but it does no harm.

The sensor's own defaults can be restored by tilting it from vertical to
upside-down 3 times within 5 seconds of power-up (RS232, 9600, N81), and 3
more inversions for RS485, 9600, N81.

## Reading rate

Readings update roughly once a second. The path is the limit, not seaView.

Measured against the bench converter with nothing else connected, a single
request-and-reply takes **305 ms**, and does so with remarkable consistency:

```
idle 0.0s -> 23 B in 304.6 ms
idle 0.5s -> 23 B in 304.9 ms
idle 1.0s -> 23 B in 304.0 ms
idle 2.0s -> 23 B in 305.1 ms
```

That caps the path at about **3 readings per second**, and seaView needs more
than one exchange per displayed reading.

Where the 305 ms goes, at 9600 baud:

| | |
|---|---|
| request on the wire | 15.6 ms |
| reply on the wire | 24.0 ms |
| network round trip | 0.8 ms |
| converter packet time | 2.0 ms |
| **accounted** | **42.4 ms** |
| **measured** | **305.0 ms** |
| **unexplained** | **262.6 ms** |

The 262 ms is a **fixed delay**, not processing time. It does not vary with how
long the link has been idle, it is unaffected by TCP options (`TCP_NODELAY`,
`TCP_QUICKACK`), and reducing the converter's UART packet time from 300 ms to
1 ms changed nothing (304.7 → 304.8 ms). The converter forwards the sensor's
free-running output promptly, so it is not slow in that direction.

Things worth trying, best first:

1. **Look for an RS485 turnaround or response delay in the converter.** A fixed
   delay of this size, invariant to everything else, has the shape of a
   configured timer. The page documented above is the converter's "Parameter"
   page; these units usually have others. Removing it would take the ceiling
   from ~3/s to roughly 20/s — by far the largest available win.
2. **Raise the baud rate from 9600 to 115200**, on the sensor (via seaView's
   device settings) and then on the converter, in that order. Worth about 36 ms
   of the 305 ms — real but modest. If the two ever disagree, the sensor's
   defaults can be restored by tilting it (see above).
3. **Check the sensor's own output rate** in its settings in seaView. If it is
   below what the link allows, raising it helps; it cannot exceed the ceiling.

Note the FMD app is a discrete-reading workflow — you position the sensor and
press **Ping**. For a continuously updating display, the **Altimeter** app is
the one to use.

## How the address gets into seaView

seaView keeps its settings in

```
~/.wine-seaview/drive_c/users/<you>/AppData/Roaming/Impact Subsea/seaView/seaview.xml
```

and reads `searchIp` and `searchIpPort` from it at startup. Step `[5/5]` writes
the values from `seaview.conf` into those fields, which is why the Devices
search opens on **NETWORK** with the address already filled in.

It stops one press short of connecting, and that is a limit of the
application rather than a choice: seaView has **no command-line interface**
(`--help` just opens the window, and the binary carries no option strings), and
its settings file has no entry for a Serial Over LAN port — only for the search
fields. So the port itself cannot be created from outside the application.

The file is rewritten by seaView when it exits, so the script only touches it
while seaView is not running.

## Removing a leftover COM port

seaView uses no serial port in this setup, so the Comms panel should contain
only `NETWORK` plus whatever Serial Over LAN port you add.

If a `COMxx` entry appears, it is left over from an earlier configuration —
most likely a machine that once ran the bridged setup described below. It costs
nothing to leave, but seaView will poll it. Remove it with:

```bash
WINEPREFIX="$HOME/.wine-seaview" wine reg delete 'HKLM\Software\Wine\Ports' /v COM11 /f
rm -f ~/.wine-seaview/dosdevices/com11
WINEPREFIX="$HOME/.wine-seaview" wineserver -k
```

substituting the port number shown. Confirm with:

```bash
WINEPREFIX="$HOME/.wine-seaview" wine reg query 'HKLM\HARDWARE\DEVICEMAP\SERIALCOMM'
```

which should report no serial devices at all.

## Why not socat and tty0tty

An earlier version of this setup bridged the converter into a virtual serial
port with `socat` and the `tty0tty` kernel module, presenting it to seaView as
a Wine COM port — the approach
[serial-over-eth](https://github.com/eyerov/serial-over-eth) uses for CP Logger.

That works for CP Logger because NOR-CPlogger has no network option and must be
handed something that looks like a COM port. seaView has serial-over-LAN built
in, so the entire bridge was unnecessary. It was removed, along with the kernel
module, the `dialout` group requirement, the build tools, and a class of
problems around the module surviving reboots and kernel upgrades.

Worth knowing if you ever compare the two repositories: they are no longer the
same architecture, deliberately.

## Known issues

- **Whether the Serial Over LAN port survives a restart is unconfirmed.** It
  does not appear in `seaview.xml`, which suggests it does not; but the one
  test that showed it missing had killed seaView outright, preventing any
  save-on-exit. Close seaView with its window button, relaunch, and see. If the
  Comms panel is empty, re-add the port as in Part 7.
- **Most converters serve one TCP session at a time.** If something else is
  connected — a terminal, a test script, another copy of seaView — the port
  will not open.
- **seaView's discovery takes the sensor out of NMEA mode.** If the vehicle
  software consumes an NMEA stream from the same sensor, running seaView
  against it will stop that stream until the sensor is power-cycled or put back
  by seaView. See the study report.
