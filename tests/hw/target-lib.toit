// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// The USB host test target: talks on the console UART (UART0 -> bridge) via
// io.stdout/io.stdin directly, bypassing the print service so logd does not
// swallow it.
//
// Output, one line each:
//   TOIT-USB-TEST <n> <uptime-us> <mac>
//                                   every second, mac in hex: tests use it to
//                                   tell whether the target is their own board
//   ECHO <line>                     for every line received
//   PONG                            for "ping"
//   BURST <i>/<n>                   n times, for "burst <n>"
//   BLOB <n> followed by n bytes    (0x20 + i % 0x5f, printable ASCII since the
//                                   console is not 8-bit clean) + "\n", for "blob <n>"
//   ERR <line>                      for anything that fails to parse

import encoding.hex
import esp32
import io

MARKER ::= "TOIT-USB-TEST"

/** Starts the heartbeat and the command loop as tasks. */
start-target -> none:
  task:: heartbeat
  task:: echo-loop

heartbeat -> none:
  mac := hex.encode esp32.mac-address
  n := 0
  while true:
    io.stdout.write "$MARKER $n $Time.monotonic-us $mac\n"
    n++
    sleep --ms=1000

echo-loop -> none:
  while true:
    line := io.stdin.read-line
    if line == null:
      sleep --ms=100
      continue
    e := catch --trace: handle line
    if e: io.stdout.write "ERR $line: $e\n"

handle line/string -> none:
  parts := line.split " "
  cmd := parts[0]
  if cmd == "ping":
    io.stdout.write "PONG\n"
  else if cmd == "burst" and parts.size == 2:
    n := int.parse parts[1] --if-error=: 0
    n.repeat: io.stdout.write "BURST $it/$n\n"
  else if cmd == "blob" and parts.size == 2:
    n := int.parse parts[1] --if-error=: 0
    blob := ByteArray n: 0x20 + it % 0x5f
    io.stdout.write "BLOB $n\n"
    io.stdout.write blob
    io.stdout.write "\n"
  else:
    io.stdout.write "ECHO $line\n"
