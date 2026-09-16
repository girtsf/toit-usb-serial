// Waits for a USB-UART bridge, then prints every line it sends and pulses
// RTS once to reset an attached ESP32 devkit.
//
// Needs a firmware with USB host support; the USB Serial/JTAG console is
// unavailable while the host is open, so run this over WiFi (Jaguar) or the
// board's UART console.

import usb.host as usb
import usb-serial show *

main:
  host := usb.Host
  try:
    device := host.wait-for-device
    print "attached: $device"
    if not supports device:
      print "no driver for this device"
      return
    port := open device --baud-rate=115200
    try:
      // RTS alone resets an ESP32 devkit, so we see it boot.
      port.set-modem-control --rts --no-dtr
      sleep --ms=50
      port.set-modem-control --no-rts --no-dtr

      port.out.write "ping\n"
      catch --trace:
        while true:
          line := port.in.read-line
          if not line: break
          print "< $line"
    finally:
      port.close
  finally:
    host.close
