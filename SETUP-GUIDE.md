# seaView — Setup Guide

**For Ubuntu 24.04**

Sets up seaView on a new machine. Parts 1–9 are one-time setup; after that,
use the [Everyday use](#everyday-use) section. Allow about 30 minutes for the
first run.

---

## Before you start

- Ubuntu 24.04
- The **seaview-over-eth** folder (this one)
- The seaView installer, `Seaview (Rev 3.1.8.2).exe`, sitting in this folder.
  It is deliberately not committed to git (80 MB), so a fresh clone will not
  have it — copy it in from the IMPACT drive if it is missing
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
cp seaview.conf.example seaview.conf
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
