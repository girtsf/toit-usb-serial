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
`TOIT-USB-TEST <n> <us>` heartbeat every second, `PONG` for `ping`,
`BURST i/n` lines for `burst n`, `n` bytes for `blob n`, and `ECHO <line>`
for everything else.

Install it on the target board and run the test on the host board:

    jag container install usb-target tests/hw/target.toit -d <target>
    jag run tests/hw/bridge-test.toit -d <host>

`bridge-test.toit` (the tests are in `bridge-tests.toit`) covers control
transfers, bulk IN and OUT, a binary blob, the RTS reset (the target's ROM
banner comes back), read timeouts that have to cancel a pending transfer, no
data loss when reads time out mid-burst, closing the port while another
task is blocked reading, and three close/reopen rounds of the whole stack.

## More tests

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
