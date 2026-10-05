// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import usb.host as usb
import .base
import .port

REQ-READ-VERSION_ ::= 0x5F
REQ-WRITE-REG_ ::= 0x9A
REQ-READ-REG_ ::= 0x95
REQ-SERIAL-INIT_ ::= 0xA1
REQ-MODEM-CTRL_ ::= 0xA4

REG-PRESCALER_ ::= 0x12
REG-DIVISOR_ ::= 0x13
REG-LCR_ ::= 0x18
REG-LCR2_ ::= 0x25

LCR-ENABLE-RX_ ::= 0x80
LCR-ENABLE-TX_ ::= 0x40
LCR-MARK-SPACE_ ::= 0x20
LCR-PAR-EVEN_ ::= 0x10
LCR-ENABLE-PAR_ ::= 0x08
LCR-STOP-BITS-2_ ::= 0x04
LCR-8N1_ ::= LCR-ENABLE-RX_ | LCR-ENABLE-TX_ | 0x03

BIT-RTS_ ::= 1 << 6
BIT-DTR_ ::= 1 << 5

CLOCK-RATE_ ::= 48_000_000
MIN-BPS_ ::= 46
MAX-BPS_ ::= 3_000_000

VENDOR-DEVICE_ ::= usb.REQUEST-TYPE-VENDOR | usb.REQUEST-RECIPIENT-DEVICE

/**
A serial port on a WCH CH340/CH341 USB-UART bridge.

The protocol follows the Linux `ch341.c` driver: vendor control requests
  configure the chip, the bulk endpoints carry the serial data.
*/
class Ch34x extends PortBase_:
  /**
  The vendor and product ids this driver handles, the same list as Linux'
    `ch341` driver.
  */
  static IDS ::= [
    [0x1A86, 0x5523],  // CH341 in serial mode.
    [0x1A86, 0x7522],  // CH340K.
    [0x1A86, 0x7523],  // CH340G/C/E.
    [0x2184, 0x0057],
    [0x4348, 0x5523],
    [0x9986, 0x7523],
  ]

  /** The chip version, as reported by the version request. */
  version/int
  baud-rate_/int := 0
  lcr_/int := LCR-8N1_

  /** Whether $device is a bridge this driver handles. */
  static matches device/usb.Device -> bool:
    return IDS.any: | ids/List | ids[0] == device.vendor-id and ids[1] == device.product-id

  /**
  Opens the CH34x $device at $baud-rate.

  Claims the device's first interface.
  DTR and RTS are left deasserted, since devkits wire them to EN and IO0.

  The $data-bits (5 to 8), $parity (one of the Port.PARITY- constants) and
    $stop-bits (1 or 2) can only be changed from 8N1 on chip versions 0x30
    and above; older chips throw "UNSUPPORTED".

  With `--no-check-ids` the vendor and product ids are not checked, for clones
    with other ids. The first interface must then have the CH34x shape: vendor
    class, a bulk IN, a bulk OUT and an interrupt IN endpoint.
  */
  constructor device/usb.Device
      --baud-rate/int=115200
      --data-bits/int=8
      --parity/int=Port.PARITY-NONE
      --stop-bits/int=1
      --check-ids/bool=true:
    if check-ids and not matches device: throw "not a CH34x: $device"
    descriptor/usb.InterfaceDescriptor := device.interfaces[0]
    if not check-ids:
      endpoints := descriptor.endpoints
      bulk := endpoints.filter: | endpoint/usb.EndpointDescriptor | endpoint.is-bulk
      interrupt := endpoints.filter: | endpoint/usb.EndpointDescriptor |
        endpoint.is-interrupt and endpoint.is-in
      if descriptor.class-code != 0xFF or endpoints.size != 3 or bulk.size != 2 or interrupt.size != 1:
        throw "not a CH34x interface: $descriptor"
    line-control := lcr --data-bits=data-bits --parity=parity --stop-bits=stop-bits
    version-bytes := device.control-in --request-type=VENDOR-DEVICE_ --request=REQ-READ-VERSION_ --length=2
    version = version-bytes.size > 0 ? version-bytes[0] : 0
    if line-control != LCR-8N1_ and version < 0x30: throw "UNSUPPORTED"
    lcr_ = line-control
    super device descriptor
    control-out_ REQ-SERIAL-INIT_ 0 0
    this.baud-rate = baud-rate
    write-modem-control_

  baud-rate -> int: return baud-rate_

  /**
  Changes the line to $new-rate baud.

  The requested rate is rounded to what the chip's prescaler and divisor can
    do; see $divisor.
  */
  baud-rate= new-rate/int -> none:
    value := divisor new-rate
    // Versions above 0x27 buffer up to a full packet unless bit 7 is set.
    if version > 0x27: value |= 1 << 7
    control-out_ REQ-WRITE-REG_ (REG-DIVISOR_ << 8 | REG-PRESCALER_) value
    // Version 0x30 and above take line control through REG_LCR.
    if version >= 0x30:
      control-out_ REQ-WRITE-REG_ (REG-LCR2_ << 8 | REG-LCR_) lcr_
    baud-rate_ = new-rate

  write-modem-control_ -> none:
    control := (dtr_ ? BIT-DTR_ : 0) | (rts_ ? BIT-RTS_ : 0)
    control-out_ REQ-MODEM-CTRL_ (~control & 0xFFFF) 0

  close-chip_ -> none:

  /** See $Port.modem-status. */
  modem-status -> int:
    bytes := device_.control-in --request-type=VENDOR-DEVICE_ --request=REQ-READ-REG_ --value=0x0706 --length=2
    if bytes.size < 1: throw "SHORT_RESPONSE"
    // CTS, DSR, RI and DCD in bits 0 to 3, active low, as in Port.
    return (~bytes[0]) & 0x0f

  control-out_ request/int value/int index/int -> none:
    device_.control-out --request-type=VENDOR-DEVICE_ --request=request --value=value --index=index

  /**
  Computes the line control register value for the given $data-bits,
    $parity and $stop-bits.
  */
  static lcr --data-bits/int --parity/int --stop-bits/int -> int:
    if not 5 <= data-bits <= 8: throw "INVALID_ARGUMENT"
    result := LCR-ENABLE-RX_ | LCR-ENABLE-TX_ | (data-bits - 5)
    if parity == Port.PARITY-ODD: result |= LCR-ENABLE-PAR_
    else if parity == Port.PARITY-EVEN: result |= LCR-ENABLE-PAR_ | LCR-PAR-EVEN_
    else if parity == Port.PARITY-MARK: result |= LCR-ENABLE-PAR_ | LCR-MARK-SPACE_
    else if parity == Port.PARITY-SPACE: result |= LCR-ENABLE-PAR_ | LCR-MARK-SPACE_ | LCR-PAR-EVEN_
    else if parity != Port.PARITY-NONE: throw "INVALID_ARGUMENT"
    if stop-bits == 2: result |= LCR-STOP-BITS-2_
    else if stop-bits != 1: throw "INVALID_ARGUMENT"
    return result

  /**
  Computes the prescaler/divisor register value for $baud-rate.

  The chip divides its 48 MHz clock:
    `baud-rate = 48000000 / (2^(12 - 3 * ps - fact) * div)`, with
    `0 <= ps <= 3`, `0 <= fact <= 1` and `2 <= div <= 256` (`fact` 0) or
    `9 <= div <= 256` (`fact` 1).
  Rates outside the chip's range are clamped to it.

  Linux' `ch341` also detects clones with a limited prescaler and avoids
    some of the encodings for them; this driver does not.
  */
  static divisor baud-rate/int -> int:
    speed := max MIN-BPS_ (min baud-rate MAX-BPS_)
    fact := 1
    ps := 3
    while ps >= 0:
      if speed > (min-rate_ ps): break
      ps--
    if ps < 0: throw "INVALID_ARGUMENT"
    clk-div := clk-div_ ps fact
    div := CLOCK-RATE_ / (clk-div * speed)
    if div < 9 or div > 255:
      div /= 2
      clk-div *= 2
      fact = 0
    if div < 2: throw "INVALID_ARGUMENT"
    // Pick the next divisor if that rate is closer to the requested one.
    if 16 * CLOCK-RATE_ / (clk-div * div) - 16 * speed >= 16 * speed - 16 * CLOCK-RATE_ / (clk-div * (div + 1)):
      div++
    // Prefer the lower base clock if the divisor is even.
    if fact == 1 and div % 2 == 0:
      div /= 2
      fact = 0
    return (0x100 - div) << 8 | fact << 2 | ps

  static clk-div_ ps/int fact/int -> int:
    return 1 << (12 - 3 * ps - fact)

  static min-rate_ ps/int -> int:
    return CLOCK-RATE_ / ((clk-div_ ps 1) * 512)
