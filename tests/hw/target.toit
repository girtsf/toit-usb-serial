// USB host test target.
//
// Runs on an ESP32 devkit whose USB-UART bridge is plugged into the host under
// test. Talks on the console UART (UART0 -> bridge) via io.stdout/io.stdin
// directly, bypassing the print service so logd does not swallow it.
//
// Output, one line each:
//   TOIT-USB-TEST <n> <uptime-ms>   every second
//   ECHO <line>                     for every line received
//   PONG                            for "ping"
//   BURST <i>/<n>                   n times, for "burst <n>"
//   BLOB <n> followed by n bytes    (0x20 + i % 0x5f, printable ASCII since the
//                                   console is not 8-bit clean) + "\n", for "blob <n>"
//   ERR <line>                      for anything that fails to parse

import io

MARKER ::= "TOIT-USB-TEST"

main:
  print "usb-target: started"  // Goes to logd, not the UART.
  task:: heartbeat
  echo-loop

heartbeat -> none:
  n := 0
  while true:
    io.stdout.write "$MARKER $n $Time.monotonic-us\n"
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
