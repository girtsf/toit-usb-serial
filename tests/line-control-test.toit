// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Checks the line control encodings of both drivers against the values the
// Linux drivers send.

import expect show *
import usb-serial show Port Ch34x Cp210x

main:
  test-ch34x
  test-cp210x

test-ch34x:
  // ch341.c: CH341_LCR_ENABLE_RX | CH341_LCR_ENABLE_TX | CH341_LCR_CS8.
  expect-equals 0xc3 (Ch34x.lcr --data-bits=8 --parity=Port.PARITY-NONE --stop-bits=1)
  expect-equals 0xc0 (Ch34x.lcr --data-bits=5 --parity=Port.PARITY-NONE --stop-bits=1)
  expect-equals 0xcb (Ch34x.lcr --data-bits=8 --parity=Port.PARITY-ODD --stop-bits=1)
  expect-equals 0xdb (Ch34x.lcr --data-bits=8 --parity=Port.PARITY-EVEN --stop-bits=1)
  expect-equals 0xeb (Ch34x.lcr --data-bits=8 --parity=Port.PARITY-MARK --stop-bits=1)
  expect-equals 0xfb (Ch34x.lcr --data-bits=8 --parity=Port.PARITY-SPACE --stop-bits=1)
  expect-equals 0xc7 (Ch34x.lcr --data-bits=8 --parity=Port.PARITY-NONE --stop-bits=2)
  expect-throw "INVALID_ARGUMENT": Ch34x.lcr --data-bits=9 --parity=Port.PARITY-NONE --stop-bits=1
  expect-throw "INVALID_ARGUMENT": Ch34x.lcr --data-bits=8 --parity=7 --stop-bits=1
  expect-throw "INVALID_ARGUMENT": Ch34x.lcr --data-bits=8 --parity=Port.PARITY-NONE --stop-bits=3

test-cp210x:
  // AN571 SET_LINE_CTL: data bits in 15:8, parity in 7:4, stop bits in 3:0.
  expect-equals 0x0800 (Cp210x.line-control --data-bits=8 --parity=Port.PARITY-NONE --stop-bits=1)
  expect-equals 0x0710 (Cp210x.line-control --data-bits=7 --parity=Port.PARITY-ODD --stop-bits=1)
  expect-equals 0x0820 (Cp210x.line-control --data-bits=8 --parity=Port.PARITY-EVEN --stop-bits=1)
  expect-equals 0x0830 (Cp210x.line-control --data-bits=8 --parity=Port.PARITY-MARK --stop-bits=1)
  expect-equals 0x0840 (Cp210x.line-control --data-bits=8 --parity=Port.PARITY-SPACE --stop-bits=1)
  expect-equals 0x0802 (Cp210x.line-control --data-bits=8 --parity=Port.PARITY-NONE --stop-bits=2)
  expect-throw "INVALID_ARGUMENT": Cp210x.line-control --data-bits=4 --parity=Port.PARITY-NONE --stop-bits=1
  expect-throw "INVALID_ARGUMENT": Cp210x.line-control --data-bits=8 --parity=5 --stop-bits=1
