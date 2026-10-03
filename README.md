# seaview-over-eth

Runs **Impact Subsea seaView** on an Ubuntu machine, with the sonar or
altimeter reached over an RS485-to-Ethernet converter instead of a serial cable
to the PC.

seaView is a Windows program. It runs here through Wine, a compatibility layer
that lets Windows software run on Linux. You do not need to know anything about
Wine to use it — the setup handles that.

**The seaView installer is in this folder**, along with the launch script and
the guides, so there is nothing to hunt down separately.

---

## Getting started

| If you want to… | Go to |
|---|---|
| **Set this up on a new machine** | **[SETUP-GUIDE.md](SETUP-GUIDE.md)** — start to finish, about 20 minutes |
| Understand why it is built this way | [SETUP-GUIDE.md](SETUP-GUIDE.md#technical-reference) — the technical reference at the end |

Once set up, day-to-day use is two commands:

```bash
cd ~/seaview-over-eth
./start-seaview.sh
```

---

## How it connects

The sensor talks RS485. Rather than running a serial cable to the PC, an
RS485-to-Ethernet converter puts that data on the network, and **seaView
connects to it directly over TCP**:

```
ISA500 / sonar head
    |  RS485
    v
RS485-to-Ethernet converter        (e.g. 192.168.2.181:23)
    |  network
    v
seaView  —  "Serial Over LAN" port
```

That is the whole path. seaView has built-in support for serial-over-LAN, so
there is no bridge, no virtual serial port, and no kernel driver in between.
The converter's address is configured **inside seaView**, under
**Comms → + → Add a Serial Over Lan Port**.

`start-seaview.sh` checks the machine is in a fit state and launches the
application. It does not carry any data.

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
| `start-seaview.sh` | Pre-launch checks, then starts seaView |
| `seaview.conf` | Your settings — converter address, Wine paths |
| `Seaview (Rev 3.1.8.2).exe` | The seaView installer |

---

## Alongside CP Logger

Both applications can run on the same machine without interfering.

CP Logger uses the [serial-over-eth](https://github.com/eyerov/serial-over-eth)
setup — socat and a tty0tty virtual serial port bridged into a Wine COM port —
because NOR-CPlogger has no network option and must be handed something that
looks like a COM port. **seaView needs none of that**, because it speaks to the
converter itself.

So the two share a machine and a Wine installation, but not an architecture.
Each keeps its own Wine environment:

| | CP Logger | seaView |
|---|---|---|
| Wine environment | `~/.wine` (32-bit) | `~/.wine-seaview` (64-bit) |
| Runtime | .NET — needs Wine Mono | Qt/C++ — no Mono |
| Path to the device | socat → tty0tty → COM10 | direct TCP |

---

## Requirements

- Ubuntu 24.04
- An RS485-to-Ethernet converter, reachable on the network
- Administrator (sudo) access, for first-time setup only
- An internet connection during setup (to install Wine)

Wine 10 or newer is required; the guide installs it. Wine 9, which Ubuntu
supplies by default, cannot run seaView reliably.
