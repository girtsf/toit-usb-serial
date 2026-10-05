// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Single-board hardware test, see README.md in this directory.
//
// Runs on an ESP32-S3 devkit with two USB ports and USB host support, with a
// cable from its native USB port to its own USB-UART port. The board is
// both host and target: the `usb-target` container must be installed on it
// too, and talks on UART0, which the bridge carries back to the USB host.

import .bridge-tests

main:
  // Resetting the target would reset the board running the test.
  run-bridge-tests --no-reset
