// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// USB host test target, installed as a container on an ESP32 devkit whose
// USB-UART bridge is plugged into the host under test. See target-lib.toit
// for what it says.

import .target-lib

main:
  print "usb-target: started"  // Goes to logd, not the UART.
  start-target
