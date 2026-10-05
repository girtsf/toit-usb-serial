// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Hardware test, see README.md in this directory.
//
// Runs on an ESP32-S2 or S3 with USB host support. A second ESP32 devkit is
// plugged into its USB port through the devkit's USB-UART bridge and runs
// `target.toit`.

import .bridge-tests

main:
  run-bridge-tests --reset
