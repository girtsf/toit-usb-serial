# Hardware test

Needs two boards:

- an ESP32-S3 with a USB host firmware, the 5V jumper on its back bridged so
  the native USB port supplies VBUS, and its UART console free for flashing;
- a second ESP32 devkit plugged into that port through its own USB-UART
  bridge, running `target.toit` as a container.

`target.toit` answers on the console UART: a `TOIT-USB-TEST <n> <us>`
heartbeat every second, `PONG` for `ping`, `BURST i/n` lines for `burst n`,
`n` bytes for `blob n`, and `ECHO <line>` for everything else.

Install it on the target board and run the test on the host board:

    jag container install usb-target tests/hw/target.toit -d <target>
    jag run tests/hw/bridge-test.toit -d <host>

`bridge-test.toit` covers control transfers, bulk IN and OUT, a binary blob,
the RTS reset (the target's ROM banner comes back), read timeouts that have
to cancel a pending transfer, and three close/reopen rounds of the whole
stack.

A USB host takes the USB Serial/JTAG console away, so if the host board's
UART console is not hooked up, follow the output with
[logd](https://github.com/girtsf/toit-logd): install its container on the
host board and run `logd-monitor <host-ip>` on the PC.

If a `usb.Host` ever fails with `ESP_ERR_INVALID_STATE`, the host stack is
wedged for the rest of that boot (IDF still has it installed, the Toit side
does not think so) and the board has to be rebooted.

The target board's console turns every `\n` into `\r\n`, including inside
the blob, so the test trims lines and expects the blob to be printable
ASCII.
