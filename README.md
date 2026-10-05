# usb-serial

Drivers for USB-UART bridge chips attached to an ESP32 running as a USB
host. The bridge shows up as a `Port` with an `io.Reader` and an
`io.Writer`, plus DTR/RTS control.

Supported chips:

| Driver   | Chips                                           | VID:PID                                                          |
| -------- | ----------------------------------------------- | ---------------------------------------------------------------- |
| `Ch34x`  | CH340G/C/E, CH340K, CH341 (serial)              | 1a86:7523, 1a86:7522, 1a86:5523, 4348:5523, 9986:7523, 2184:0057 |
| `Cp210x` | CP2102, CP2102N, CP2104, CP2109, CP2105, CP2108 | 10c4:ea60, 10c4:ea70, 10c4:ea71                                  |

Tested on hardware: CH340K and CP2102N.

CH340 clones with a limited prescaler (Linux' `ch341` detects them and
avoids some baud rate encodings) are not handled: a few rates, 9600 among
them, come out wrong on those.

## Requirements

The USB side comes from the SDK's `usb.host` library, which needs firmware
built with `CONFIG_TOIT_ENABLE_USB_HOST` on an ESP32-S2 or ESP32-S3 (both
tested). The host takes over the USB PHY, which means the USB Serial/JTAG
console is gone while a `usb.Host` is open; use the UART console or run over
WiFi.

On the ESP32-S2, the stock firmware configuration keeps the Toit heap in
internal RAM even on boards with PSRAM, which leaves little room for
programs. Build it with `CONFIG_TOIT_SPIRAM_HEAP=y` and
`CONFIG_SPIRAM_USE_MALLOC=y` if the board has PSRAM.

The bridge is powered from the host's USB port, and many ESP32 devkits
don't supply VBUS on it: a diode between the connector and the 5V rail only
lets power flow into the board. Bridge the diode (some boards have a solder
jumper for this) or power the bridge some other way.

Hubs are not supported: exactly one device at a time.

## Example Usage

```toit
import usb.host as usb
import usb-serial

main:
  host := usb.Host
  try:
    device := host.wait-for-device      // Blocks until something is plugged in.
    port := usb-serial.open device --baud-rate=115200
    port.out.write "ping\n"
    print port.in.read-line
    port.close
  finally:
    host.close                          // Also closes the device.
```

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

## Tests

`make test` runs the host tests (divisor and line control encodings).
`tests/hw/` has hardware tests, most of them for two boards; see its README.

## AI Disclosure

Robots wrote most of this.
