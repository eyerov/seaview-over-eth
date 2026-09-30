# seaView — Setup Guide

**For Ubuntu 24.04**

Sets up seaView on a new machine. Parts 1–9 are one-time setup; after that,
use the [Everyday use](#everyday-use) section. Allow about 30 minutes for the
first run.

---

## Before you start

- Ubuntu 24.04
- The **seaview-over-eth** folder (this one)
- Nothing else to download: the seaView installer and the driver source are
  both in this folder
- The administrator password for the machine
- The converter's **IP address** (e.g. `192.168.2.125`) and its **raw data
  port** (often `2000`; some converters use `23`)
- The converter powered on and connected to the network
- An internet connection for the first-time setup

> **No converter yet?** Everything except the converter itself can still be
> checked — see [Testing without a converter](#testing-without-a-converter)
> at the end. No extra hardware is needed.

---

## Part 1 — Open the folder

```bash
cd ~/seaview-over-eth
```

Confirm you are in the right place:

```bash
ls
```

The listing should include `install-tty0tty.sh` and `start-seaview.sh`.

---

## Part 2 — Make the scripts executable

```bash
chmod +x install-tty0tty.sh start-seaview.sh
```

No output means it worked.

---

## Part 3 — Install Wine

**seaView needs Wine 10 or newer.** Ubuntu's own Wine package is version 9,
which cannot run seaView — it starts, then closes by itself after about ten
seconds. Install WineHQ's version instead:

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
sudo apt update && sudo apt install --install-recommends winehq-stable socat
```

This downloads several hundred megabytes and takes a few minutes.

Check the version:

```bash
wine --version
```

You should see **`wine-10.0` or higher** (for example `wine-11.0`). If it
prints `wine-9.0`, the WineHQ steps above did not take effect — run them
again before continuing.

---

## Part 4 — Create the Wine environment

seaView is a 64-bit program and needs a 64-bit Wine environment. The default
one on Ubuntu is 32-bit, which will not work.

```bash
WINEARCH=win64 WINEPREFIX="$HOME/.wine-seaview" WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -u
```

The first Wine command on a new machine takes a minute or two. Wait for it to
return you to the prompt.

Confirm:

```bash
head -5 ~/.wine-seaview/system.reg | grep arch
```

This must print `#arch=win64`. If it prints `#arch=win32`, delete the folder
and run the command again:

```bash
rm -rf ~/.wine-seaview
```

---

## Part 5 — Install the driver

Installs the virtual serial-port driver (tty0tty) that carries data from the
converter into seaView.

The driver source is included in this folder (`tty0tty/`), so this works
without an internet connection.

```bash
./install-tty0tty.sh
```

It prompts for your password and takes 1–2 minutes. It finishes with:

```
=== Done ===
crw-rw---- 1 root dialout 505, 0 ... /dev/tnt0
...
```

If you see `[FAILED]`, go to [Troubleshooting](#troubleshooting).

---

## Part 6 — Log out and back in

**Required.** The installer adds your account to the `dialout` group, which
grants access to the serial ports. Group changes do not apply to a session
that is already running.

Log out and log back in, or reboot.

---

## Part 7 — Install seaView

The installer is in this folder. From here:

```bash
cd ~/seaview-over-eth
WINEPREFIX="$HOME/.wine-seaview" wine "Seaview (Rev 3.1.8.2).exe"
```

The installer window opens. Work through it and **accept the default
options**, including the default install location.

Confirm where it landed:

```bash
WINEPREFIX="$HOME/.wine-seaview" find ~/.wine-seaview/drive_c -name 'seaView.exe' -exec winepath -w {} \;
```

This prints the program's Windows path, normally:

```
C:\Program Files\Impact Subsea\seaView\seaView.exe
```

**Copy this line** — you may need it in Part 8. If nothing is printed, the
installation did not complete; run the installer again.

---

## Part 8 — Configure

```bash
cd ~/seaview-over-eth
gnome-text-editor seaview.conf
```

Set these two values to match your converter:

```
CONVERTER_IP="192.168.2.125"
CONVERTER_PORT="2000"
```

Change only the text inside the quotation marks, and keep the quotation
marks.

> The port must be the one the converter serves **raw data** on. Many
> converters use a different port for their settings menu. If you are unsure,
> check the converter's manual.

Then check the `SEAVIEW_EXE` line:

```
SEAVIEW_EXE='C:\Program Files\Impact Subsea\seaView\seaView.exe'
```

If it does not match the path you copied in Part 7, replace it with that
path, keeping the single quotation marks at both ends.

Save with **Ctrl + S** and close the editor.

---

## Part 9 — Make COM11 the only port

**Do not skip this.** Without it seaView's display is slow and jerky.

seaView checks every serial port Windows offers it, over and over. Linux
pretends to have 32 serial ports even when the machine has none, so seaView
spends all its time checking ports that do not exist. Removing them leaves
**COM11 as the only port**, which is what the setup is designed around.

First confirm this machine has no real serial port on its motherboard:

```bash
cat /sys/class/tty/ttyS0/type
```

If this prints **`0`**, the ports are imaginary and safe to remove — continue.
If it prints anything else, the machine has real serial hardware; skip to
Part 10 and mention it when reporting any slowness.

Remove them:

```bash
sudo sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 8250.nr_uarts=0"/' /etc/default/grub
```

```bash
sudo update-grub
```

Then **reboot**.

After rebooting, check it worked:

```bash
ls /dev/ttyS* 2>/dev/null | wc -l
```

This should print **`0`**. If it still prints `32`, the change did not apply —
see [Troubleshooting](#troubleshooting).

> If `0` causes any problem on this machine, use `8250.nr_uarts=1` instead and
> re-run the two commands above. That leaves one harmless port, so seaView
> sees two instead of one — still far better than 33.

---

## Part 10 — Start seaView

```bash
cd ~/seaview-over-eth
./start-seaview.sh
```

The script runs through eight numbered steps and then launches seaView. Once
the program is open, go to its port settings and select **COM11**.

Near the top of its output you should see:

```
Serial ports Wine will expose: COM11 only (as designed).
```

If instead it warns that Wine will auto-detect other devices, Part 9 has not
taken effect — the display will be sluggish until it does.

Leaving the terminal open lets you see any errors the script reports.

---

## Everyday use

```bash
cd ~/seaview-over-eth
./start-seaview.sh
```

Then select **COM11** in seaView.

Use the same two commands after a reboot — the script reloads the driver
automatically. Parts 1–9 do not need repeating.

### Stopping

Close seaView normally. The background bridge is left running deliberately,
so the link survives reopening the program. To stop it:

```bash
pkill socat
```

> **If CP Logger is also installed on this machine**, `pkill socat` stops
> *its* bridge too. Stop only seaView's by matching its converter:
>
> ```bash
> pkill -f "socat.*192.168.2.125"
> ```
>
> seaView uses **COM11** and CP Logger uses **COM10**, so the two never get
> confused for each other.

---

## Testing without a converter

The whole setup can be checked with no hardware at all — no converter, no
cables. This brings up COM11 over exactly the same path, just with nothing
feeding it:

```bash
cd ~/seaview-over-eth
./start-seaview.sh --transport loopback --feed
```

`--feed` writes a test line into the port once a second, so you can confirm
data reaches seaView. Select **COM11** in seaView as usual.

This checks everything except the converter itself: Wine, the seaView install,
the driver, the port mapping, and that COM11 is the only port. Useful for
confirming a machine is ready before it goes to the vessel.

Parts 7 and 8 (converter settings) are not needed for this.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| seaView closes by itself after ~10 seconds | Wine is too old. Check `wine --version` — it must be 10 or higher. Redo Part 3. |
| `Bad EXE format` | The Wine environment is 32-bit. Redo Part 4. |
| seaView is slow and jerky | Part 9 was skipped, or did not apply. The start script should say `COM11 only (as designed)`. Check `ls /dev/ttyS* 2>/dev/null \| wc -l` — it should be `0`. |
| `Permission denied` running a script | Part 2 was skipped — run the `chmod +x` command, then retry. |
| Program opens but shows no data | Wrong IP or port. Recheck Part 8. Confirm the converter is powered on and on the network. |
| Data appears but is unreadable | The converter's own baud rate does not match the device. Set it in the converter, not in seaView. |
| `ERROR: converter IP not set` | Part 8 was missed, or the file was not saved. |
| `wine: command not found` | Wine is not installed. Run Part 3. |
| `ERROR: 'socat' is not installed` | Run `sudo apt install -y socat`, then retry. |
| `ERROR: socat exited immediately` | A previous bridge is still running. Run `pkill socat`, wait 5 seconds, retry. |
| `COM11` missing from seaView's port list | Close seaView, re-run `./start-seaview.sh`, and wait for step `[8/8]` before opening port settings. |
| `[FAILED] Could not install/load tty0tty` | Usually no internet connection to download the driver source. Check connectivity and re-run Part 5. |
| Ports show `root root` instead of `root dialout` | Part 6 was skipped. Log out and back in. |
| Still 32 ports after Part 9 | The GRUB edit did not apply. Open `/etc/default/grub`, check `GRUB_CMDLINE_LINUX_DEFAULT` contains `8250.nr_uarts=0`, then re-run `sudo update-grub` and reboot. |

### Reporting a problem

Include the output of all three commands:

```bash
wine --version
```

```bash
lsmod | grep tty0tty
```

```bash
tail -20 /tmp/socat-seaview.log
```

along with the error message shown on screen.

---

## Quick reference

| Task | Command |
|---|---|
| Go to the folder | `cd ~/seaview-over-eth` |
| Start seaView | `./start-seaview.sh` |
| Test with no hardware | `./start-seaview.sh --transport loopback --feed` |
| Stop the bridge | `pkill socat` |
| Edit settings | `gnome-text-editor seaview.conf` |
| Check the connection log | `tail -20 /tmp/socat-seaview.log` |
| Port to select in seaView | `COM11` |

---

# Technical reference

Everything above is the procedure. This section is the reasoning behind it —
read it when something does not behave, or before changing the setup.

## Why Wine 10 or newer

**Wine 9 and earlier cannot run seaView at all.** A few seconds after seaView
opens a serial port the process dies with:

```
Unhandled exception: page fault on read access to 0x0000000000000000
ntdll.so+0x35a0b:  mov (%rdi),%rdi
```

Wine ≤ 9 implements `WaitCommEvent` by spawning a worker thread per wait
(`dlls/ntdll/unix/serial.c`); that thread can start with a null argument and
faults on its first dereference. Wine 10 replaced the path with the Wine
server's async I/O and the crashing function no longer exists.

It matters here specifically because the trigger is a *virtual* port. On a
real onboard `/dev/ttyS*` port an event is always already pending, so the
faulty thread is never created and the bug stays hidden. A tty0tty device —
what this setup uses — creates it every time.

Ubuntu 24.04 ships Wine 9.0, so the distribution package will not do.
`start-seaview.sh` refuses to launch on anything older than 10 rather than
let it fail confusingly.

## Why the Wine environment must be 64-bit

`seaView.exe` is a 64-bit binary. The **installer** is 32-bit and runs happily
in a 32-bit environment — leaving behind an application that can never start,
failing with `Bad EXE format`. Nothing about the installation reports a
problem; the failure only appears at launch.

Ubuntu's default `~/.wine` is 32-bit, which is why this setup keeps its own at
`~/.wine-seaview`. The start script checks and refuses to run against a 32-bit
one.

## One port, by design

seaView opens and polls **every COM port Windows offers it**, continuously, on
the thread that also draws its display. The intended end state is therefore
exactly one port: **COM11 and nothing else.**

That is achievable because of how Wine discovers ports. Its startup scan looks
at precisely three patterns:

```
/dev/ttyS*    /dev/ttyUSB*    /dev/ttyACM*
```

`/dev/tnt*` is **not** among them. A tty0tty device can only become a COM port
by being named in `HKLM\Software\Wine\Ports`, which is what step 8 of the start
script does. So the bridge contributes one port and one only, and anything Wine
auto-detects is an *extra* port seaView will poll.

On a machine with no serial hardware the kernel still creates 32 `/dev/ttyS*`
nodes, and Wine turns each into a COM port. Measured on this machine:

| | Before (Part 9 skipped) | After |
|---|---|---|
| Serial devices Wine exposes | 34 | **1** |
| Display thread CPU | 97.2% | **0.2%** |
| Frame rate | 0.6 fps | **~10 fps** |
| Internal port errors in 20 s | 3466 | **0** |

One thing to expect: with nothing answering on COM11, seaView keeps a
background thread busy at roughly half a CPU core, looking for a device. That
does not slow the display — the drawing thread is idle — but it is normal on
this setup and not a fault.

**There is no way to restrict this from inside Wine.** Tested on Wine 11: an
environment with every port link deleted and only COM11 registered still came
back with 33 devices after restarting. The registry key *adds* ports; it never
limits them. The only lever is what exists in `/dev`, which is why Part 9 works
on the kernel command line.

This helps CP Logger too: its COM10 also arrives through the registry over a
tty0tty device, so neither application depends on `/dev/ttyS*` existing.

## Baud rate over the bridge

**The baud rate selected in seaView does nothing.** It configures a virtual
port with no hardware behind it. The real serial settings — 115200 8N1 for an
ISA500 at defaults — live in the **converter's own configuration** and must be
set there.

This is the most common cause of "the port opens but the data is unreadable":
Wine faithfully applies a baud rate to a virtual port while the converter talks
at a different one.

## Verifying the connection

```bash
tail -f /tmp/socat-seaview.log        # "write(" lines mean data is arriving
cat /dev/tnt1                          # read the raw stream without seaView
wine reg query "HKLM\Software\Wine\Ports" /v COM11
```

To test the converter with nothing else in the path:

```bash
socat - tcp:192.168.2.125:2000
```

If that shows nothing, the problem is the converter, its IP, its port, or the
wiring — not this setup.

## Running alongside CP Logger

| | CP Logger | seaView |
|---|---|---|
| Wine environment | `~/.wine` (**32-bit**) | `~/.wine-seaview` (**64-bit**) |
| Runtime | .NET — needs Wine Mono | Qt/C++ — no Mono |
| COM port | `COM10` | `COM11` |
| tty0tty pair | e.g. `/dev/tnt2` ↔ `/dev/tnt3` | a **different** pair |
| Network bridge | its own | its own |

The Wine **program** is shared system-wide; the **environments** are
independent. One Wine 11 install serves both.

`HKLM\Software\Wine\Ports` lives inside each environment, so COM10 and COM11
would not actually collide even if both used the same number. Distinct numbers
are for clarity, so a port name identifies its application.

If both run at once, give each its own tty0tty pair via `TNT_PAIR` in
`seaview.conf`, set to something CP Logger's config does not use.

## Differences from serial-over-eth

This follows the same architecture as
[serial-over-eth](https://github.com/eyerov/serial-over-eth) (NOR-CP-Logger).
Four things differ:

| | serial-over-eth | seaview-over-eth |
|---|---|---|
| Wine environment | 32-bit, stock `~/.wine` | **64-bit**, `~/.wine-seaview` |
| Runtime | .NET — needs Wine Mono | Qt/C++ — **no Mono** |
| Wine version | 11 in practice | **≥ 10 enforced**; 9 is fatal |
| Port selection | operator picks a port | **scans every port** — hence Part 9 |

Everything else — socat, tty0tty, the registry mapping, the config and flag
precedence, and `install-tty0tty.sh` itself — carries over unchanged.

## Installing seaView without the wizard

Part 7 can run headless, which is useful when imaging several machines:

```bash
cd ~/seaview-over-eth
WINEPREFIX="$HOME/.wine-seaview" wine "Seaview (Rev 3.1.8.2).exe" install \
    --root 'C:\Program Files\Impact Subsea\seaView' \
    --accept-licenses --default-answer --confirm-command
```

## Known issues

- **The driver does not survive a reboot** when built and loaded this way.
  `start-seaview.sh` step 1 reloads it automatically, so this is handled — but
  `lsmod` will show it only after the start script has run once.
- **Kernel upgrades break the built driver.** Re-run `./install-tty0tty.sh`.
  Registering it with DKMS would automate this; not wired up yet.
- **Upstream tty0tty documents testing up to kernel 6.12.x.** Newer kernels may
  need a source update before it compiles.
- **Modem control lines do not cross the bridge.** DTR/RTS asserted by Wine on
  a `tnt` device do not reach the converter's RS485 side. Converters that draw
  power from handshake pins will not work over Ethernet — power them properly.
- **RS485 turnaround timing is the converter's problem.** Half-duplex direction
  control happens inside the converter; the network adds latency and jitter
  that a tightly-timed polling protocol may not tolerate. See the study
  report's risk register.
