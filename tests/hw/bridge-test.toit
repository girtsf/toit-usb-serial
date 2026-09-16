// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

// Hardware test, see README.md in this directory.
//
// Runs on an ESP32-S3 with USB host support. A second ESP32 devkit is
// plugged into its USB port through the devkit's USB-UART bridge and runs
// `target.toit`.

import expect show *
import io
import usb.host as usb
import usb-serial show *
import usb-serial.ch34x show Ch34x
import usb-serial.cp210x show Cp210x

BAUD-RATE ::= 115200

main:
  test-conversation
  test-reset
  test-timeouts
  test-reopen
  print "all tests passed"

/** Opens the bridge, expecting exactly one device to be attached. */
with-port [block] -> none:
  host := usb.Host
  try:
    device := host.wait-for-device
    print "attached: $device"
    expect (supports device) --message="no driver for $device"
    port := open device --baud-rate=BAUD-RATE
    try:
      describe port
      block.call port
    finally:
      port.close
      device.close
  finally:
    host.close

describe port/Port -> none:
  if port is Cp210x:
    cp210x := port as Cp210x
    // Reads the rate back from the chip: a control transfer in both directions.
    expect-equals BAUD-RATE cp210x.baud-rate
    print "cp210x: baud-rate $cp210x.baud-rate modem-status 0x$(%02x cp210x.modem-status)"
  else if port is Ch34x:
    ch34x := port as Ch34x
    print "ch34x: version 0x$(%02x ch34x.version) modem-status 0x$(%02x ch34x.modem-status)"

/** Bulk IN and OUT: heartbeat, echo, a burst of lines and a binary blob. */
test-conversation -> none:
  with-port: | port/Port |
    heartbeat := read-prefixed port.in "TOIT-USB-TEST"
    print "heartbeat: $heartbeat"

    port.out.write "ping\n"
    expect-equals "PONG" (read-prefixed port.in "PONG").trim

    port.out.write "hello from the host\n"
    echo := read-prefixed port.in "ECHO"
    expect-equals "ECHO hello from the host" echo.trim

    port.out.write "burst 5\n"
    5.repeat: | i |
      expect-equals "BURST $i/5" (read-prefixed port.in "BURST").trim

    port.out.write "blob 300\n"
    expect-equals "BLOB 300" (read-prefixed port.in "BLOB").trim
    blob := port.in.read-bytes 302
    // The target's console turns the trailing \n into \r\n.
    expect-equals (ByteArray 300: 0x20 + it % 0x5f) blob[..300]
    expect-equals "\r\n".to-byte-array blob[300..]

/** Modem control: RTS alone resets the target, which then prints its ROM banner. */
test-reset -> none:
  with-port: | port/Port |
    expect-not port.rts
    port.set-modem-control --rts --no-dtr
    expect port.rts
    sleep --ms=50
    port.set-modem-control --no-rts --no-dtr
    print "rom: $(read-prefixed port.in "ESP-ROM")"
    print "back up: $(read-prefixed port.in "TOIT-USB-TEST")"

/** A read that times out must cancel its transfer without breaking the next one. */
test-timeouts -> none:
  with-port: | port/Port |
    timeouts := 0
    reads := 0
    // The target only talks once a second, so most 150 ms reads time out.
    20.repeat:
      e := catch:
        with-timeout --ms=150:
          port.in.read
          reads++
      if e == DEADLINE-EXCEEDED-ERROR: timeouts++
      else if e: throw e
    print "$timeouts timeouts, $reads reads"
    expect timeouts > 0
    print "still alive: $(read-prefixed port.in "TOIT-USB-TEST")"

/** Closing and reopening the whole stack must leave it usable. */
test-reopen -> none:
  3.repeat: | round |
    with-port: | port/Port |
      print "round $round: $(read-prefixed port.in "TOIT-USB-TEST")"

/**
Reads lines until one starts with $prefix.

Junk bytes can precede the first full line after the bridge is initialized.
*/
read-prefixed reader/io.Reader prefix/string --timeout-ms/int=5_000 -> string:
  with-timeout --ms=timeout-ms:
    while true:
      line/string? := null
      e := catch: line = reader.read-line
      if e == "ILLEGAL_UTF_8": continue
      if e: throw e
      if not line: throw "EOF"
      if line.starts-with prefix: return line
  unreachable
