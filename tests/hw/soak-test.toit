// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Randomized soak test on the two-board setup (see README.md in this
// directory). First a long session on one open port: echoes, bursts and
// blobs of random sizes, all checked byte for byte. Then open/close cycles
// that tear down a random level (port, device, host) at a random moment
// while data is flowing, each followed by a check that the bridge still
// answers. Prints the heap now and then and expects it not to shrink.

import expect show *
import usb.host as usb
import usb-serial as serial
import usb-serial show Port
import .bridge-tests show read-prefixed BAUD-RATE
import .corner-test show free-heap start-reader

SESSION-MS ::= 5 * 60_000
CYCLES-MS ::= 5 * 60_000

main:
  seed := Time.monotonic-us
  set-random-seed "$seed"
  print "seed $seed"
  test-session
  test-cycles
  print "all tests passed"

test-session -> none:
  host := usb.Host
  try:
    device := host.wait-for-device
    port := serial.open device --baud-rate=BAUD-RATE
    try:
      read-prefixed port.in "TOIT-USB-TEST"
      counts := {"echo": 0, "burst": 0, "blob": 0}
      bytes := 0
      start := Time.monotonic-us
      last-report := start
      while Time.monotonic-us - start < SESSION-MS * 1000:
        choice := random 3
        if choice == 0:
          bytes += echo port
          counts["echo"]++
        else if choice == 1:
          bytes += burst port (1 + (random 300))
          counts["burst"]++
        else:
          bytes += blob port (1 + (random 8_000))
          counts["blob"]++
        if Time.monotonic-us - last-report > 30_000_000:
          last-report = Time.monotonic-us
          print "session: $counts, $(bytes / 1024) KB, heap $free-heap"
      print "session: $counts, $(bytes / 1024) KB: ok"
    finally:
      port.close
      device.close
  finally:
    host.close

/** Sends a few random lines without waiting and checks their echoes. */
echo port/Port -> int:
  lines := List (1 + (random 3)): random-line
  lines.do: port.out.write "$it\n"
  received := 0
  lines.do: | line/string |
    echo := read-prefixed port.in "ECHO"
    expect-equals "ECHO $line" echo
    received += echo.size
  return received

random-line -> string:
  chars := "abcdefghijklmnopqrstuvwxyz0123456789 -_"
  length := 1 + (random 80)
  // A leading 'x' keeps the line from being a command.
  return "x" + (string.from-runes (List length: chars[random chars.size]))

burst port/Port n/int -> int:
  port.out.write "burst $n\n"
  received := 0
  n.repeat: | i |
    line := read-prefixed port.in "BURST"
    expect-equals "BURST $i/$n" line.trim
    received += line.size
  return received

blob port/Port n/int -> int:
  port.out.write "blob $n\n"
  read-prefixed port.in "BLOB $n"
  data := with-timeout --ms=10_000: port.in.read-bytes n + 2
  expect-equals (ByteArray n: 0x20 + it % 0x5f) data[..n]
  expect-equals "\r\n".to-byte-array data[n..]
  return n

test-cycles -> none:
  counts := {"port": 0, "device": 0, "host": 0}
  start := Time.monotonic-us
  free := []
  while Time.monotonic-us - start < CYCLES-MS * 1000:
    level := ["port", "device", "host"][random 3]
    cycle level
    counts[level]++
    total := counts["port"] + counts["device"] + counts["host"]
    if total % 25 == 0:
      free.add free-heap
      print "cycles: $counts, heap $free.last"
  print "cycles: $counts, heap $free"
  // The free heap moves by a 4 KB page now and then; a leak of part of a
  //   Host per cycle would be far more.
  if free.size >= 3: expect (free[1] - free.last) < 8_000
  print "cycles: ok"

/**
Opens everything, starts a blob, and closes the given level after a random
  delay while the reader is busy. Then checks that the bridge still answers.
*/
cycle level/string -> none:
  host := usb.Host
  try:
    device := host.wait-for-device
    port := serial.open device --baud-rate=BAUD-RATE
    reader := start-reader port
    port.out.write "blob $(1 + (random 5_000))\n"
    sleep --ms=(random 300)
    if level == "port": port.close
    else if level == "device": device.close
    else: host.close
    result := with-timeout --ms=2_000: reader.get
    expect-null result[0]
    port.close
    if level != "host":
      if level == "device": device = host.wait-for-device
      check-alive device
  finally:
    host.close
  if level == "host":
    host = usb.Host
    try:
      check-alive host.wait-for-device
    finally:
      host.close

check-alive device/usb.Device -> none:
  port := serial.open device --baud-rate=BAUD-RATE
  try:
    // A canceled blob may still be queued on the target.
    port.out.write "\nping\n"
    read-prefixed port.in "PONG" --timeout-ms=20_000
  finally:
    port.close
