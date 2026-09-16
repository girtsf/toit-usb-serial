# usb-serial

Drivers for USB-UART bridge chips attached to an ESP32 running as a USB
host. The bridge shows up as a `Port` with an `io.Reader` and an
`io.Writer`, plus DTR/RTS control.

Supported chips:

| Driver   | Chips                         | VID:PID                     |
| -------- | ----------------------------- | --------------------------- |
| `Ch34x`  | CH340G/C, CH340K, CH341       | 1a86:7523, 7522, 5523, 5512 |
| `Cp210x` | CP2102/CP2109, CP2105, CP2108 | 10c4:ea60, ea70, ea71       |

## Requirements

The USB side comes from the SDK's `usb.host` library, so this package needs
a firmware built with USB host support on a chip with a USB-OTG peripheral
(ESP32-S2/S3/P4). The host takes over the USB PHY, which means the USB
Serial/JTAG console is gone while a `usb.Host` is open; use the UART console
or run over WiFi.

The bridge is powered from the host's USB port, and many ESP32 devkits
don't supply VBUS on it: a diode between the connector and the 5V rail only
lets power flow into the board. Bridge the diode (some boards have a solder
jumper for this) or power the bridge some other way.

Hubs are not supported: exactly one device at a time.

## Usage

```toit
import usb.host as usb
import usb-serial show *

main:
  host := usb.Host
  device := host.wait-for-device        // Blocks until something is plugged in.
  port := open device --baud-rate=115200
  port.out.write "ping\n"
  print port.in.read-line
  port.close
  device.close
  host.close
```

`open` picks the driver by vendor and product id; `supports device` tells you
whether there is one. The chip specific classes can also be constructed
directly (`Cp210x device --interface-number=1` for the second port of a
CP2105), and they expose what their chip can do on top of `Port`: the CP210x
reads its baud rate back and can purge its buffers, the CH34x reports its
version and takes raw line control bits.

### DTR and RTS

Both drivers leave DTR and RTS deasserted when they open the port, because
ESP32 devkits wire them to the auto-reset circuit: RTS alone holds the
attached board in reset, DTR alone pulls IO0 low. Pulsing RTS resets the
board:

```toit
port.set-modem-control --rts --no-dtr
sleep --ms=50
port.set-modem-control --no-rts --no-dtr
```

## AI Disclosure

Robots wrote most of this.
