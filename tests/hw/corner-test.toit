// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Hardware test for teardown corner cases, on the two-board setup (see
// README.md in this directory): closing at every level while data is
// flowing, interrupted opens, a process that dies with the port open, and
// misuse that must fail cleanly.

import expect show *
import monitor
import system
import usb.host as usb
import usb-serial as serial
import usb-serial show Port
import .bridge-tests show read-prefixed BAUD-RATE

main:
  test-port-close-while-streaming
  test-device-close-while-streaming
  test-host-close-while-streaming
  test-close-wakes-writer
  test-transfer-in-while-streaming
  test-second-host
  test-second-port
  test-interrupted-open
  test-process-exit-while-streaming
  test-finalizer
  free := [free-heap]
  2.repeat:
    5.repeat: test-port-close-while-streaming --rounds=3
    free.add free-heap
  print "heap: $free"
  // A Host costs about 13 KB; losing part of one per round would show.
  //   Other processes shift the free heap by a 4 KB page now and then; a
  //   real leak shows in both halves, so the smaller loss is what counts.
  expect (min free[0] - free[1] free[1] - free[2]) < 4_000
  print "all tests passed"

with-device [block] -> none:
  host := usb.Host
  try:
    device := host.wait-for-device
    try:
      block.call host device
    finally:
      device.close
  finally:
    host.close

/** Expects the bridge to answer, after junk from earlier rounds. */
expect-alive port/Port -> none:
  // A canceled write may have left a partial line on the target.
  port.out.write "\nping\n"
  // Blobs from earlier rounds may still be queued on the target.
  read-prefixed port.in "PONG" --timeout-ms=20_000

/**
Reads in a task until the port returns null or throws, and returns a
  latch with the exception (or null) and the byte count.
*/
start-reader port/Port -> monitor.Latch:
  latch := monitor.Latch
  task::
    count := 0
    exception := catch --trace:
      while data := port.in.read: count += data.size
    latch.set [exception, count]
  return latch

/** Closes the port while a reader is busy and the target is sending. */
test-port-close-while-streaming --rounds/int=30 -> none:
  with-device: | host/usb.Host device/usb.Device |
    rounds.repeat: | round |
      port := serial.open device --baud-rate=BAUD-RATE
      reader := start-reader port
      port.out.write "blob 1000\n"
      sleep --ms=(round * 37 % 200)
      port.close
      result := with-timeout --ms=2_000: reader.get
      expect-null result[0]
    port := serial.open device --baud-rate=BAUD-RATE
    try:
      expect-alive port
    finally:
      port.close
  print "port close while streaming: ok"

/** Closes the device under an open port. */
test-device-close-while-streaming -> none:
  host := usb.Host
  try:
    10.repeat: | round |
      device := host.wait-for-device
      port := serial.open device --baud-rate=BAUD-RATE
      reader := start-reader port
      port.out.write "blob 1000\n"
      sleep --ms=(round * 53 % 200)
      device.close
      result := with-timeout --ms=2_000: reader.get
      expect-null result[0]
      // Closing the port afterwards must be harmless.
      port.close
    device := host.wait-for-device
    port := serial.open device --baud-rate=BAUD-RATE
    expect-alive port
    port.close
    device.close
  finally:
    host.close
  print "device close while streaming: ok"

/** Closes the host under an open device and port. */
test-host-close-while-streaming -> none:
  10.repeat: | round |
    host := usb.Host
    device := host.wait-for-device
    port := serial.open device --baud-rate=BAUD-RATE
    reader := start-reader port
    port.out.write "blob 1000\n"
    sleep --ms=(round * 53 % 200)
    host.close
    result := with-timeout --ms=2_000: reader.get
    expect-null result[0]
    port.close
  with-device: | host device |
    port := serial.open device --baud-rate=BAUD-RATE
    expect-alive port
    port.close
  print "host close while streaming: ok"

/** Closing the port ends a long write in another task. */
test-close-wakes-writer -> none:
  with-device: | host/usb.Host device/usb.Device |
    port := serial.open device --baud-rate=BAUD-RATE
    writer := monitor.Latch
    task::
      line := ("x" * 63 + "\n").to-byte-array
      exception := catch:
        500.repeat: port.out.write line
      writer.set exception
    sleep --ms=300
    port.close
    exception := with-timeout --ms=2_000: writer.get
    print "writer ended with: $exception"
    expect-equals "WRITER_CLOSED" exception
    port = serial.open device --baud-rate=BAUD-RATE
    try:
      expect-alive port
    finally:
      port.close
  print "close wakes writer: ok"

/**
A transfer-in on the streamed endpoint fails without stealing the
  stream reader's wake-up.
*/
test-transfer-in-while-streaming -> none:
  with-device: | host/usb.Host device/usb.Device |
    port := serial.open device --baud-rate=BAUD-RATE
    try:
      in := device.interfaces[0].endpoints.filter: | e/usb.EndpointDescriptor | e.is-bulk and e.is-in
      // Wait for a quiet moment right after a heartbeat.
      read-prefixed port.in "TOIT-USB-TEST"
      reader := monitor.Latch
      task:: reader.set (read-prefixed port.in "TOIT-USB-TEST")
      sleep --ms=100
      expect-throw "ALREADY_IN_USE": device.transfer-in in[0]
      print "next heartbeat: $(with-timeout --ms=3_000: reader.get)"
    finally:
      port.close
  print "transfer-in while streaming: ok"

test-second-host -> none:
  host := usb.Host
  try:
    expect-throw "ALREADY_IN_USE": usb.Host
    device := host.wait-for-device
    expect-throw "ALREADY_IN_USE": host.wait-for-device
    device.close
  finally:
    host.close
  print "second host: ok"

/** Opening the same interface twice fails and leaves the first port working. */
test-second-port -> none:
  with-device: | host/usb.Host device/usb.Device |
    port := serial.open device --baud-rate=BAUD-RATE
    try:
      exception := catch: serial.open device --baud-rate=BAUD-RATE
      expect-equals "ALREADY_IN_USE" exception
      expect-alive port
    finally:
      port.close
    port = serial.open device --baud-rate=BAUD-RATE
    try:
      expect-alive port
    finally:
      port.close
  print "second port: ok"

/** Opens interrupted at every step must clean up after themselves. */
test-interrupted-open -> none:
  with-device: | host/usb.Host device/usb.Device |
    opened := 0
    ((List 60: it % 12 + 1) + [15, 20, 30, 50]).do: | ms/int |
      port/Port? := null
      exception := catch:
        with-timeout --ms=ms:
          port = serial.open device --baud-rate=BAUD-RATE
      if exception: expect-equals DEADLINE-EXCEEDED-ERROR exception
      if port:
        opened++
        port.close
    print "$opened of 64 opens completed"
    port := serial.open device --baud-rate=BAUD-RATE
    try:
      expect-alive port
    finally:
      port.close
  print "interrupted open: ok"

/**
A process that exits with everything open must not keep the stack.

(A process that crashes takes the whole program down with it under Jaguar,
  so that case can't be tested from here.)
*/
test-process-exit-while-streaming -> none:
  3.repeat:
    child := spawn::
      host := usb.Host
      device := host.wait-for-device
      port := serial.open device --baud-rate=BAUD-RATE
      port.out.write "blob 20000\n"
      task:: while port.in.read: null
      sleep --ms=300
      exit 0
    with-timeout --ms=10_000:
      // Reading the priority of a dead process throws.
      while not (catch: child.priority):
        sleep --ms=50
    host/usb.Host? := null
    with-timeout --ms=5_000:
      while not host:
        exception := catch: host = usb.Host
        if exception:
          print "  after child exit: $exception"
          sleep --ms=100
    try:
      device := host.wait-for-device
      port := serial.open device --baud-rate=BAUD-RATE
      expect-alive port
      port.close
      device.close
    finally:
      host.close
  print "process exit while streaming: ok"

/** An unreachable Host is closed by its finalizer. */
test-finalizer -> none:
  create-and-drop
  host/usb.Host? := null
  with-timeout --ms=5_000:
    while not host:
      exception := catch: host = usb.Host
      if exception:
        expect-equals "ALREADY_IN_USE" exception
        system.process-stats --gc
        sleep --ms=50
  host.close
  print "finalizer: ok"

create-and-drop -> none:
  host := usb.Host
  device := host.wait-for-device
  port := serial.open device --baud-rate=BAUD-RATE
  port.out.write "blob 1000\n"

free-heap -> int:
  result := 0
  3.repeat:
    if it > 0: sleep --ms=200
    stats := system.process-stats --gc
    free := stats[system.STATS-INDEX-SYSTEM-FREE-MEMORY] + stats[system.STATS-INDEX-RESERVED-MEMORY]
    result = max result free
  return result
