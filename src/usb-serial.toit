// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import io
import usb.host as usb
import .port
import .ch34x
import .cp210x

export Port Ch34x Cp210x

/**
Drivers for USB-UART bridge chips attached to a USB host.

The USB side comes from the SDK's `usb.host` library, which needs a firmware
  built with USB host support on an ESP32-S2 or ESP32-S3. This package adds
  the chip specific configuration and presents the bridge as a $Port with an
  $io.Reader and an $io.Writer.

Entry points:
- $open picks the driver for a `usb.Device` by vendor and product id, and
  $supports tells whether there is one.
- $Ch34x and $Cp210x can be constructed directly, for example to open the
  second port of a CP2105.

Gotchas:
- A $Port does not own the device: close the port, then the device, then the
  `usb.Host`.
- Reads return null when the port is closed or the device is unplugged.
- Both drivers leave DTR and RTS deasserted, since ESP32 devkits wire them
  to their reset circuit.

# Examples
```
import usb.host as usb
import usb-serial

main:
  host := usb.Host
  try:
    device := host.wait-for-device
    port := usb-serial.open device --baud-rate=115200
    port.out.write "ping\n"
    print port.in.read-line
    port.close
  finally:
    host.close
```
*/

/** Whether this package has a driver for $device. */
supports device/usb.Device -> bool:
  return (Ch34x.matches device) or (Cp210x.matches device)

/**
Opens $device as a serial $Port at $baud-rate.

See $Ch34x.constructor and $Cp210x.constructor for $data-bits, $parity,
  $stop-bits and $read-buffer-size.

Picks the driver by vendor and product id. Throws if $device is not a bridge
  this package knows; use $supports to check first.
*/
open device/usb.Device
    --baud-rate/int=115200
    --data-bits/int=8
    --parity/int=Port.PARITY-NONE
    --stop-bits/int=1
    --read-buffer-size/int=4096
    -> Port:
  if Ch34x.matches device:
    return Ch34x device
        --baud-rate=baud-rate
        --data-bits=data-bits
        --parity=parity
        --stop-bits=stop-bits
        --read-buffer-size=read-buffer-size
  if Cp210x.matches device:
    return Cp210x device
        --baud-rate=baud-rate
        --data-bits=data-bits
        --parity=parity
        --stop-bits=stop-bits
        --read-buffer-size=read-buffer-size
  throw "no USB-UART driver for $device"
