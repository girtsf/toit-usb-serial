// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/**
Driver for the WCH CH340/CH341 USB-UART bridges.

The protocol follows the Linux `ch341.c` driver: vendor control requests
  configure the chip, the bulk endpoints carry the serial data.
*/

import io
import usb.host as usb
import .port

/** The WCH vendor id. */
VID ::= 0x1A86
/** The product ids this driver handles: CH340G/C, CH340K and CH341. */
PIDS ::= [0x7523, 0x7522, 0x5523, 0x5512]

REQ-READ-VERSION_ ::= 0x5F
REQ-WRITE-REG_ ::= 0x9A
REQ-READ-REG_ ::= 0x95
REQ-SERIAL-INIT_ ::= 0xA1
REQ-MODEM-CTRL_ ::= 0xA4

REG-BREAK_ ::= 0x05
REG-PRESCALER_ ::= 0x12
REG-DIVISOR_ ::= 0x13
REG-LCR_ ::= 0x18
REG-LCR2_ ::= 0x25

/** Line control bit: enable the receiver. */
LCR-ENABLE-RX ::= 0x80
/** Line control bit: enable the transmitter. */
LCR-ENABLE-TX ::= 0x40
/** Line control bit: send the parity bit as mark/space instead of even/odd. */
LCR-MARK-SPACE ::= 0x20
/** Line control bit: even parity instead of odd. */
LCR-PAR-EVEN ::= 0x10
/** Line control bit: enable parity. */
LCR-ENABLE-PAR ::= 0x08
/** Line control bit: two stop bits instead of one. */
LCR-STOP-BITS-2 ::= 0x04
/** Line control bits: 8 data bits. */
LCR-CS8 ::= 0x03
/** Line control for 8N1, receiver and transmitter enabled. */
LCR-8N1 ::= LCR-ENABLE-RX | LCR-ENABLE-TX | LCR-CS8

BIT-RTS_ ::= 1 << 6
BIT-DTR_ ::= 1 << 5

CLOCK-RATE_ ::= 48_000_000
MIN-BPS_ ::= 46
MAX-BPS_ ::= 3_000_000

VENDOR-DEVICE_ ::= usb.TYPE-VENDOR | usb.RECIPIENT-DEVICE

/** A serial port on a CH340/CH341 bridge. */
class Ch34x extends Object with io.InMixin io.OutMixin implements Port:
  device_/usb.Device
  in-endpoint_/int
  out-endpoint_/int
  in-max_/int
  /** The chip version, as reported by the version request. */
  version/int
  dtr_/bool := false
  rts_/bool := false
  is-closed_/bool := false

  /** Whether $device is a bridge this driver handles. */
  static matches device/usb.Device -> bool:
    return device.vid == VID and PIDS.contains device.pid

  /**
  Opens the CH34x $device at $baud-rate, 8N1.

  Claims the device's first interface.
  DTR and RTS are left deasserted, since devkits wire them to EN and IO0.

  With `--no-check-ids` the vendor and product ids are not checked, for clones
    with other ids. The first interface must then have the CH34x shape: vendor
    class, a bulk IN, a bulk OUT and an interrupt IN endpoint.
  */
  constructor device/usb.Device --baud-rate/int=115200 --check-ids/bool=true:
    if check-ids and not matches device: throw "not a CH34x: $device"
    device_ = device
    iface := device.interfaces[0]
    in := iface.endpoints.filter: it.is-bulk and it.is-in
    out := iface.endpoints.filter: it.is-bulk and not it.is-in
    if in.is-empty or out.is-empty: throw "no bulk endpoints: $iface"
    if not check-ids:
      interrupt := iface.endpoints.filter: it.type == usb.Endpoint.TYPE-INTERRUPT and it.is-in
      if iface.class-code != 0xFF or iface.endpoints.size != 3 or in.size != 1 or out.size != 1 or interrupt.size != 1:
        throw "not a CH34x interface: $iface"
    in-endpoint_ = in[0].address
    out-endpoint_ = out[0].address
    in-max_ = in[0].max-packet-size
    device.claim-interface iface.number

    version-bytes := device.control-in --request-type=VENDOR-DEVICE_ --request=REQ-READ-VERSION_ --length=2
    version = version-bytes.size > 0 ? version-bytes[0] : 0
    control-out_ REQ-SERIAL-INIT_ 0 0
    set-baud-rate baud-rate
    set-handshake_

  is-closed -> bool: return is-closed_

  /** See $Port.close. */
  close -> none:
    if is-closed_: return
    is-closed_ = true
    mark-reader-closed_
    mark-writer-closed_
    catch: device_.release-interface device_.interfaces[0].number

  /**
  Changes the line to $baud-rate with the line control bits $lcr.

  The requested rate is rounded to what the chip's prescaler and divisor can
    do; see $divisor.
  */
  set-baud-rate baud-rate/int --lcr/int=LCR-8N1 -> none:
    value := divisor baud-rate
    // Versions above 0x27 buffer up to a full packet unless bit 7 is set.
    if version > 0x27: value |= 1 << 7
    control-out_ REQ-WRITE-REG_ (REG-DIVISOR_ << 8 | REG-PRESCALER_) value
    // Version 0x30 and above take line control through REG_LCR.
    if version >= 0x30:
      control-out_ REQ-WRITE-REG_ (REG-LCR2_ << 8 | REG-LCR_) lcr

  dtr -> bool: return dtr_

  rts -> bool: return rts_

  /** See $Port.set-modem-control. */
  set-modem-control --dtr/bool=dtr_ --rts/bool=rts_ -> none:
    dtr_ = dtr
    rts_ = rts
    set-handshake_

  set-handshake_ -> none:
    control := (dtr_ ? BIT-DTR_ : 0) | (rts_ ? BIT-RTS_ : 0)
    control-out_ REQ-MODEM-CTRL_ (~control & 0xFFFF) 0

  /** The modem status: CTS, DSR, RI and DCD in bits 0 to 3, active high. */
  modem-status -> int:
    bytes := device_.control-in --request-type=VENDOR-DEVICE_ --request=REQ-READ-REG_ --value=0x0706 --length=2
    return (~bytes[0]) & 0x0f

  control-out_ request/int value/int index/int -> none:
    device_.control-out --request-type=VENDOR-DEVICE_ --request=request --value=value --index=index

  /** Reads whatever the bridge has, at most one bulk transfer. */
  read_ -> ByteArray?:
    if is-closed_: return null
    max := in-max_ * (512 / in-max_)
    while true:
      data := device_.bulk-in in-endpoint_ --max=max
      if data.size > 0: return data

  try-write_ data/io.Data from/int to/int -> int:
    if is-closed_: throw "CLOSED"
    bytes := data is ByteArray ? (data as ByteArray)[from..to] : (ByteArray.from data from to)
    device_.bulk-out out-endpoint_ bytes
    return to - from

  /**
  Computes the prescaler/divisor register value for $baud-rate.

  The chip divides its 48 MHz clock:
    `baud-rate = 48000000 / (2^(12 - 3 * ps - fact) * div)`, with
    `0 <= ps <= 3`, `0 <= fact <= 1` and `2 <= div <= 256` (`fact` 0) or
    `9 <= div <= 256` (`fact` 1).
  Rates outside the chip's range are clamped to it.
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
