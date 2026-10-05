// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import io

/**
The common surface of the USB-UART bridge drivers.

Data flows through $in and $out; the chip specific classes (Ch34x, Cp210x)
  add whatever else their chip can do. The names follow the SDK's `uart.Port`
  where they overlap.
*/
interface Port:
  /** No parity bit. */
  static PARITY-NONE ::= 0
  /** Odd parity. */
  static PARITY-ODD ::= 1
  /** Even parity. */
  static PARITY-EVEN ::= 2
  /** The parity bit is always 1. */
  static PARITY-MARK ::= 3
  /** The parity bit is always 0. */
  static PARITY-SPACE ::= 4

  /** Modem status bit: Clear To Send. */
  static MODEM-CTS ::= 1 << 0
  /** Modem status bit: Data Set Ready. */
  static MODEM-DSR ::= 1 << 1
  /** Modem status bit: Ring Indicator. */
  static MODEM-RI ::= 1 << 2
  /** Modem status bit: Data Carrier Detect. */
  static MODEM-DCD ::= 1 << 3

  /**
  The reader for data coming from the serial line.

  Reads return null once the port is closed or the device is unplugged.
  */
  in -> io.Reader

  /** The writer for data going out on the serial line. */
  out -> io.Writer

  /** The baud rate that was last requested. */
  baud-rate -> int

  /** Changes the line to $new-rate baud. */
  baud-rate= new-rate/int -> none

  /** Whether DTR is asserted. */
  dtr -> bool

  /** Whether RTS is asserted. */
  rts -> bool

  /**
  Asserts or deasserts $dtr and $rts.

  On an ESP32 devkit these drive the auto-reset circuit: RTS alone holds the
    attached board in reset, DTR alone pulls IO0 low.

  If the request fails, $dtr and $rts keep their old values.
  */
  set-modem-control --dtr/bool --rts/bool -> none

  /**
  Reads the modem status lines.

  Returns a combination of $MODEM-CTS, $MODEM-DSR, $MODEM-RI and $MODEM-DCD,
    for the lines that are active.
  */
  modem-status -> int

  /** Whether the port has been closed. */
  is-closed -> bool

  /**
  Closes the port: stops a pending read, deasserts DTR and RTS and releases
    the interface.

  The USB device the port was opened on stays open.
  */
  close -> none
