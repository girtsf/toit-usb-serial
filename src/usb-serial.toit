// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/**
Drivers for USB-UART bridge chips attached to a USB host.

The USB side comes from the SDK's `usb.host` library, which needs a firmware
  built with USB host support. This package adds the chip specific
  configuration and presents the bridge as a $Port with an $io.Reader and an
  $io.Writer.

Example:
```
import usb.host as usb
import usb-serial show *

main:
  host := usb.Host
  device := host.wait-for-device
  port := open device --baud-rate=115200
  port.out.write "ping\n"
  print port.in.read-line
  port.close
  device.close
  host.close
```
*/

import io
import usb.host as usb
import .port
import .ch34x
import .cp210x

export *

/** Whether this package has a driver for $device. */
supports device/usb.Device -> bool:
  return (Ch34x.matches device) or (Cp210x.matches device)

/**
Opens $device as a serial $Port at $baud-rate, 8N1.

Picks the driver by vendor and product id. Throws if $device is not a bridge
  this package knows; use $supports to check first.
*/
open device/usb.Device --baud-rate/int=115200 -> Port:
  if Ch34x.matches device: return Ch34x device --baud-rate=baud-rate
  if Cp210x.matches device: return Cp210x device --baud-rate=baud-rate
  throw "no USB-UART driver for $device"
