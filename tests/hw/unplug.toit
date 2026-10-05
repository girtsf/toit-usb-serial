// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Manual unplug test for the two-board setup: reads from the target and
// pings it every second. Pull the cable whenever you like; the port's reader
// must end (null), and after replugging the next session must pick the
// target up again. Runs until killed.

import io
import usb.host as usb
import usb-serial

main:
  host := usb.Host
  session := 0
  while true:
    session++
    print "session $session: waiting for the device (plug it in)"
    device := host.wait-for-device
    port := usb-serial.open device
    print "session $session: $device -- UNPLUG WHENEVER YOU LIKE"
    pinger := task:: ping port.out
    lines := 0
    e := catch:
      while line := port.in.read-line:
        lines++
        if lines % 5 == 0: print "session $session: $lines lines, last: $line.trim"
    print "session $session: reader ended after $lines lines: $(e ? e : "EOF") (gone: $device.is-gone)"
    pinger.cancel
    port.close
    device.close

ping writer/io.Writer -> none:
  while true:
    sleep --ms=1_000
    e := catch: writer.write "ping\n"
    if e:
      print "pinger: write failed: $e"
      return
