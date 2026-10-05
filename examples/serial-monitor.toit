// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Waits for a USB-UART bridge, then prints every line it sends and pulses
// RTS once to reset an attached ESP32 devkit.
//
// Needs a firmware with USB host support; the USB Serial/JTAG console is
// unavailable while the host is open, so run this over WiFi (Jaguar) or the
// board's UART console.

import usb.host as usb
import usb-serial

main:
  host := usb.Host
  try:
    device := host.wait-for-device
    print "attached: $device"
    if not usb-serial.supports device:
      print "no driver for this device"
      return
    port := usb-serial.open device --baud-rate=115200
    try:
      // RTS alone resets an ESP32 devkit, so we see it boot.
      port.set-modem-control --rts --no-dtr
      sleep --ms=50
      port.set-modem-control --no-rts --no-dtr

      port.out.write "ping\n"
      // Ends when the bridge is unplugged.
      while line := port.in.read-line:
        print "< $line"
    finally:
      port.close
  finally:
    host.close
