# seaview-over-eth

Runs **Impact Subsea seaView** on an Ubuntu machine, with the sonar or
altimeter connected over an RS485-to-Ethernet converter instead of a serial
cable to the PC.

seaView is a Windows program. It runs here through Wine, a compatibility layer
that lets Windows software run on Linux. You do not need to know anything about
Wine to use it — the setup handles that.

**The seaView installer is in this folder**, along with the scripts and the
configuration, so there is nothing to hunt down separately. The one thing
fetched during setup is the virtual serial-port driver, which the installer
script downloads for you.

---

## Getting started

| If you want to… | Go to |
|---|---|
| **Set this up on a new machine** | **[SETUP-GUIDE.md](SETUP-GUIDE.md)** — start to finish, about 30 minutes |
| Understand why it is built this way | [STUDY-REPORT.md](STUDY-REPORT.md) — design analysis and risks |

Once set up, day-to-day use is two commands:

```bash
cd ~/seaview-over-eth
./start-seaview.sh
```

Then pick **COM11** in seaView's port settings.

---

## How it connects

The altimeter talks RS485. Rather than running a serial cable to the PC, an
RS485-to-Ethernet converter puts that data on the network, and this setup
delivers it to seaView as an ordinary serial port:

```
ISA500 / sonar head
    |  RS485
    v
RS485-to-Ethernet converter        (e.g. 192.168.2.125:2000)
    |  network
    v
socat                              (carries the data in)
    |
    v
/dev/tnt0  <---- virtual cable ---->  /dev/tnt1
                                          |
                                          v
                                    seaView's COM11
```

The two `/dev/tnt` devices behave like a serial cable with its two ends in the
same machine. Data arrives from the network at one end, and seaView reads it
from the other as **COM11**, exactly as though the instrument were plugged into
a serial port on the PC.

`start-seaview.sh` builds this path each time it runs, then opens seaView. It
prints eight numbered steps as it goes, so a failure points at the stage that
caused it.

### Why an Ethernet converter

It puts the vehicle-side electronics where they belong rather than beside the
topside PC: longer runs than RS485-to-USB comfortably allows, galvanic
isolation from the PC, and no dependency on a USB adapter staying plugged into
a particular socket.

---

## What is in this folder

| File | What it is |
|---|---|
| `SETUP-GUIDE.md` | Installation, everyday use, troubleshooting, technical reference |
| `STUDY-REPORT.md` | Why the architecture is what it is; risks and open questions |
| `start-seaview.sh` | Builds the connection and launches seaView |
| `install-tty0tty.sh` | Installs the virtual serial-port driver |
| `seaview.conf` | Your settings — converter address, port name, paths |
| `Seaview (Rev 3.1.8.2).exe` | The seaView installer |
| `tty0tty/` | Driver source — not in the repository; `install-tty0tty.sh` fetches it |

---

## Testing without a converter

The whole setup can be checked before any hardware is connected:

```bash
./start-seaview.sh --transport loopback --feed
```

This builds the same COM11 path with a test pattern behind it instead of a
converter, so a machine can be confirmed ready before it goes to the vessel.

---

## Alongside CP Logger

Both applications can run on the same machine. seaView uses **COM11**; CP
Logger uses **COM10**. They keep separate Windows environments and separate
network bridges, so neither disturbs the other.

One thing to know: `pkill socat` stops **both**. To stop only seaView's link,
match its converter address —
`pkill -f "socat.*192.168.2.125"`.

---

## Requirements

- Ubuntu 24.04
- An RS485-to-Ethernet converter, reachable on the network
- Administrator (sudo) access on the machine, for first-time setup only
- An internet connection during setup (for Wine and the driver source)

Wine 10 or newer is required; the guide installs it. Wine 9, which Ubuntu
supplies by default, cannot run seaView.
