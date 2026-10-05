// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Hardware test under load, on the two-board setup (see README.md in this
// directory): large transfers with a slow reader, reads, writes and control
// transfers at the same time, interrupted control transfers, and stdin
// started around a Host.

import expect show *
import io
import monitor
import usb.host as usb
import usb-serial as serial
import usb-serial show Port Cp210x Ch34x
import .bridge-tests show read-prefixed BAUD-RATE

main:
  test-stdin-before-host
  with-port: | port/Port |
    test-blob-slow-reader port
    test-echo-full-duplex port
    test-control-while-streaming port
    test-interrupted-control port
    test-baud-change-while-streaming port
  test-stdin-after-host
  test-device-close-during-control
  print "all tests passed"

with-port [block] -> none:
  host := usb.Host
  try:
    device := host.wait-for-device
    port := serial.open device --baud-rate=BAUD-RATE
    try:
      block.call port
    finally:
      port.close
      device.close
  finally:
    host.close

expect-alive port/Port -> none:
  port.out.write "\nping\n"
  read-prefixed port.in "PONG" --timeout-ms=20_000

/** A 20 KB blob arrives intact although the reader keeps pausing. */
test-blob-slow-reader port/Port -> none:
  n := 20_000
  port.out.write "blob $n\n"
  read-prefixed port.in "BLOB $n"
  received := io.Buffer
  pauses := 0
  with-timeout --ms=10_000:
    while received.size < n:
      received.write port.in.read
      // 40 ms is about 460 bytes at 115200 baud, more than the bridge
      //   buffers on its own.
      sleep --ms=(pauses++ % 5) * 10
  expect-equals (ByteArray n: 0x20 + it % 0x5f) received.bytes[..n]
  print "blob of $n with a slow reader: ok"

/** Writes and reads at full speed in both directions. */
test-echo-full-duplex port/Port -> none:
  count := 300
  writer := monitor.Latch
  task::
    writer.set (catch:
      count.repeat: port.out.write "line $it $("x" * 40)\n")
  with-timeout --ms=20_000:
    count.repeat: | i |
      line := read-prefixed port.in "ECHO line"
      expect-equals "ECHO line $i $("x" * 40)" line.trim
  expect-null writer.get
  print "$count lines echoed while writing: ok"

/** Control transfers, reads and writes all in flight together. */
test-control-while-streaming port/Port -> none:
  done := false
  controls := 0
  task::
    while not done:
      port.modem-status
      if port is Cp210x: expect-equals BAUD-RATE (port as Cp210x).read-baud-rate
      controls++
  port.out.write "burst 200\n"
  with-timeout --ms=10_000:
    200.repeat: | i |
      expect-equals "BURST $i/200" (read-prefixed port.in "BURST").trim
  done = true
  print "$controls control transfer rounds during a burst: ok"

/** Control transfers interrupted by timeouts leave the next ones working. */
test-interrupted-control port/Port -> none:
  timeouts := 0
  50.repeat: | i |
    exception := catch:
      with-timeout --us=(i % 10) * 200 + 100:
        port.modem-status
    if exception == DEADLINE-EXCEEDED-ERROR: timeouts++
    else if exception: throw exception
  10.repeat: port.modem-status
  expect-alive port
  print "$timeouts of 50 control transfers interrupted: ok"

/** Changing the baud rate while data arrives garbles it but breaks nothing. */
test-baud-change-while-streaming port/Port -> none:
  port.out.write "blob 5000\n"
  sleep --ms=100
  [9600, 230400, BAUD-RATE].do: | rate |
    port.baud-rate = rate
    catch: with-timeout --ms=50: port.in.read
  expect-alive port
  print "baud change while streaming: ok"

/** stdin started before a Host: the Host must still get the PHY. */
test-stdin-before-host -> none:
  reader := task --background::
    catch: io.stdin.read
  sleep --ms=100
  with-port: | port/Port | expect-alive port
  reader.cancel
  print "stdin before host: ok"

/** stdin started while a Host is open must not take the PHY away. */
test-stdin-after-host -> none:
  host := usb.Host
  try:
    reader := task --background::
      catch: io.stdin.read
    sleep --ms=100
    device := host.wait-for-device
    port := serial.open device --baud-rate=BAUD-RATE
    expect-alive port
    port.close
    device.close
    reader.cancel
  finally:
    host.close
  print "stdin after host: ok"

/** Closing the device under a task busy with control transfers. */
test-device-close-during-control -> none:
  host := usb.Host
  try:
    5.repeat: | round |
      device := host.wait-for-device
      port := serial.open device --baud-rate=BAUD-RATE
      result := monitor.Latch
      task::
        result.set (catch: while true: port.modem-status)
      sleep --ms=(round * 7 % 30)
      device.close
      exception := with-timeout --ms=3_000: result.get
      expect-equals "CLOSED" exception
      port.close
    device := host.wait-for-device
    port := serial.open device --baud-rate=BAUD-RATE
    expect-alive port
    port.close
    device.close
  finally:
    host.close
  print "device close during control transfers: ok"
