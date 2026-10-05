// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Opens a Host and closes it again at different points: right away, while
// the device is being enumerated, and after opening the device. Every close
// uninstalls the host stack, which only works in one particular order; a
// broken teardown shows up as an exception from the next Host or as heap
// that is not returned.
//
// Runs on the host board of the two-board setup, or on the loopback board;
// any USB device will do.

import expect show *
import system
import usb.host as usb

main:
  // The first batch absorbs one-time allocations (the first installs keep
  //   a few KB until reboot). Other processes shift the free heap by a page
  //   now and then; a real leak shows in every batch, so the smaller of two
  //   consecutive losses is what counts.
  batch
  free := [free-heap]
  2.repeat:
    batch
    free.add free-heap
  host := usb.Host
  device/usb.Device? := null
  try:
    with-timeout --ms=5_000:
      device = host.wait-for-device
  finally:
    host.close
  print "still works: $device"
  print "free heap after each batch: $free"
  // A Host costs about 13 KB; losing even part of one per round would show.
  expect (min free[0] - free[1] free[1] - free[2]) < 2_000
  print "all tests passed"

/** Opens and closes the host 24 times at different points. */
batch -> none:
  [0, 20, 50, 100, 200, 300, 500].do: | delay/int |
    3.repeat: round --delay=delay
  3.repeat: round --open-device

round --delay/int=0 --open-device/bool=false -> none:
  host := usb.Host
  try:
    if open-device:
      with-timeout --ms=5_000:
        host.wait-for-device
    else:
      sleep --ms=delay
  finally:
    host.close

/**
Returns the free system heap plus this process's own heap.

The process's heap grows by 4 KB pages as the test runs, which is not USB
  memory. Other processes (WiFi, logd) make it dip by a few KB at times, so
  this takes the highest of a few samples.
*/
free-heap -> int:
  result := 0
  3.repeat:
    if it > 0: sleep --ms=200
    stats := system.process-stats --gc
    free := stats[system.STATS-INDEX-SYSTEM-FREE-MEMORY] + stats[system.STATS-INDEX-RESERVED-MEMORY]
    result = max result free
  return result
