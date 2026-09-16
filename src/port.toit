// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import io

/**
The common surface of the USB-UART bridge drivers.

Data flows through $in and $out; the chip specific classes (Ch34x, Cp210x)
  add whatever else their chip can do.
*/
interface Port:
  /** The reader for data coming from the serial line. */
  in -> io.Reader

  /** The writer for data going out on the serial line. */
  out -> io.Writer

  /** Changes the line to $baud-rate. */
  set-baud-rate baud-rate/int -> none

  /** Whether DTR is asserted. */
  dtr -> bool

  /** Whether RTS is asserted. */
  rts -> bool

  /**
  Asserts or deasserts $dtr and $rts.

  On an ESP32 devkit these drive the auto-reset circuit: RTS alone holds the
    attached board in reset, DTR alone pulls IO0 low.
  */
  set-modem-control --dtr/bool --rts/bool -> none

  /** Whether the port has been closed. */
  is-closed -> bool

  /**
  Closes the port and releases the interface.

  The USB device the port was opened on stays open.
  */
  close -> none
