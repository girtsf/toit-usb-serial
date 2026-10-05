// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// The USB-UART bridge tests, shared by bridge-test.toit (two boards) and
// loopback-test.toit (one board).

import expect show *
import io
import monitor
import usb.host as usb
import usb-serial show Port Ch34x Cp210x
import usb-serial as serial

BAUD-RATE ::= 115200

/**
Runs all tests against the one attached bridge.

With `--no-reset` the RTS reset test is skipped, for a bridge that is wired
  to the board running the tests.
*/
run-bridge-tests --reset/bool -> none:
  test-conversation
  if reset: test-reset
  test-timeouts
  test-no-loss-across-timeouts
  test-close-wakes-reader
  test-reopen
  print "all tests passed"

/** Opens the bridge, expecting exactly one device to be attached. */
with-port [block] -> none:
  host := usb.Host
  try:
    device := host.wait-for-device
    print "attached: $device"
    expect (serial.supports device) --message="no driver for $device"
    port := serial.open device --baud-rate=BAUD-RATE
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
    expect-equals BAUD-RATE cp210x.read-baud-rate
    print "cp210x: baud-rate $cp210x.read-baud-rate modem-status 0x$(%02x cp210x.modem-status)"
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

/**
Reads that time out in the middle of a burst must not lose data: bytes that
  arrive just before a cancel are kept for the next read.
*/
test-no-loss-across-timeouts -> none:
  with-port: | port/Port |
    read-prefixed port.in "TOIT-USB-TEST"
    count := 300
    port.out.write "burst $count\n"
    buffer := io.Buffer
    timeouts := 0
    deadline := Time.monotonic-us + 10_000_000
    last := "BURST $(count - 1)/$count"
    done := false
    while not done:
      if Time.monotonic-us > deadline: throw "burst did not complete"
      e := catch:
        with-timeout --ms=2:
          data := port.in.read
          buffer.write data
          // The last line ends the burst; only look near the end.
          tail := buffer.bytes[max 0 (buffer.size - 40)..]
          done = tail.to-string-non-throwing.contains last
      if e == DEADLINE-EXCEEDED-ERROR: timeouts++
      else if e: throw e
    lines := buffer.bytes.to-string-non-throwing.split "\n"
    bursts := lines.filter: | line/string | line.starts-with "BURST "
    count.repeat: | i/int |
      expect-equals "BURST $i/$count" bursts[i].trim
    print "$count lines intact across $timeouts timeouts"

/** Closing the port wakes up a read blocked in another task with null. */
test-close-wakes-reader -> none:
  with-port: | port/Port |
    reader-done := monitor.Latch
    task::
      result := catch:
        while port.in.read: null
      reader-done.set result
    // The target only talks once a second, so the reader is blocked.
    sleep --ms=300
    port.close
    with-timeout --ms=2_000:
      expect-null reader-done.get

/** Closing and reopening the whole stack must leave it usable. */
test-reopen -> none:
  3.repeat: | round |
    with-port: | port/Port |
      print "round $round: $(read-prefixed port.in "TOIT-USB-TEST")"

/**
Reads lines until one starts with $prefix.

Junk bytes can precede the first full line after the bridge is initialized,
  or arrive at the wrong baud rate.
*/
read-prefixed reader/io.Reader prefix/string --timeout-ms/int=5_000 -> string:
  with-timeout --ms=timeout-ms:
    while true:
      // Junk isn't necessarily valid UTF-8, and read-line throws on it
      //   without consuming the line.
      line := (reader.read-bytes-up-to '\n').to-string-non-throwing
      if line.ends-with "\r": line = line[..line.size - 1]
      if line.starts-with prefix: return line
  unreachable
