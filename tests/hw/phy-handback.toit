// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Manual check of the PHY hand-back, for a board whose native USB port is
// plugged into a PC: while the Host is open, the board's USB Serial/JTAG
// device disappears from the PC, and it comes back when the Host is closed.

import usb.host as usb

main:
  host := usb.Host
  print "host open: USB Serial/JTAG should be GONE from the PC for 15 s"
  sleep --ms=15_000
  host.close
  print "host closed: USB Serial/JTAG should be BACK on the PC"
