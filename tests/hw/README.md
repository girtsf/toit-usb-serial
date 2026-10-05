# Hardware tests

These need a firmware with USB host support (`CONFIG_TOIT_ENABLE_USB_HOST`)
on an ESP32-S2 or ESP32-S3 (both tested), with the board's native USB port
supplying VBUS (on many devkits that means bridging a 5V jumper or diode).

## Two boards

- the host: the ESP32-S2 or ESP32-S3 above, with its UART console free
  for flashing;
- the target: a second ESP32 devkit plugged into the host's native USB port
  through its own USB-UART bridge, running `target.toit` as a container.

The target answers on its console UART (see `target-lib.toit`): a
`TOIT-USB-TEST <n> <us> <mac>` heartbeat every second, `PONG` for `ping`,
`BURST i/n` lines for `burst n`, `n` bytes for `blob n`, and `ECHO <line>`
for everything else.

Install it on the target board and run the test on the host board:

    jag container install usb-target tests/hw/target.toit -d <target>
    jag run tests/hw/bridge-test.toit -d <host>

`bridge-test.toit` (the tests are in `bridge-tests.toit`) covers control
transfers, bulk IN and OUT, a binary blob, the RTS reset (the target's ROM
banner comes back), read timeouts, no data loss when reads time out
mid-burst, closing the port while another
task is blocked reading, and three close/reopen rounds of the whole stack.

## One board

`loopback-test.toit` needs a single ESP32-S3 devkit with two USB ports: a
cable from its native USB port to its own USB-UART port, and power from
somewhere else (its 5V pin, for example). The board is both host and target:

    jag container install usb-target tests/hw/target.toit -d <board>
    jag run tests/hw/loopback-test.toit -d <board>

The target must run as a container, not in the test program: writing to
the console blocks the writing process while UART0 sends, which would
starve the test's reads. It runs the bridge tests without the RTS reset,
which would hold the board in reset until its power is cut
(`bridge-test.toit` refuses to run when the heartbeat carries its own
MAC). logd copies prints to the console, so the test's own output shows up
in what the bridge receives; the tests only look at lines with their own
prefixes.

## More tests

On the two-board setup, after `bridge-test.toit`:

- `corner-test.toit` closes the port, the device and the host while data
  is flowing and a reader is busy, closes the port under a long write,
  interrupts opens at every step with timeouts, lets a spawned process
  exit with everything open, leaves a Host to its finalizer, and checks
  misuse (a second Host, a second port, `transfer-in` on a streamed
  endpoint). It ends with a heap check.
- `load-test.toit` sends a 20 KB blob to a reader that keeps pausing,
  echoes lines while writing, runs control transfers during a burst,
  interrupts control transfers, changes the baud rate while data arrives,
  closes the device under a task busy with control transfers, and starts
  stdin before and while a Host is open.

Any setup:

- `teardown-stress-test.toit` opens and closes the host at different points
  (right away, during enumeration, after opening the device) and checks that
  the stack keeps working and no heap is lost. Any attached USB device will
  do.
- `unplug.toit` is manual: it talks to the target until you pull the cable,
  and must pick the target up again when you replug it.
- `phy-handback.toit` is manual, for a host board whose native port is
  plugged into a PC: the board's USB Serial/JTAG device must disappear from
  the PC while the host is open and come back when it closes.

## Output

A USB host takes the USB Serial/JTAG console away, so if the host board's
UART console is not hooked up, follow the output with
[logd](https://github.com/girtsf/toit-logd): install its container on the
host board and run `logd-monitor <host-ip>` on the PC.

The target board's console turns every `\n` into `\r\n`, including inside
the blob, so the test trims lines and expects the blob to be printable
ASCII.
