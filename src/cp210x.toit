// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import io
import usb.host as usb
import .base
import .port

REQ-IFC-ENABLE_ ::= 0x00
REQ-SET-LINE-CTL_ ::= 0x03
REQ-SET-MHS_ ::= 0x07
REQ-GET-MDMSTS_ ::= 0x08
REQ-PURGE_ ::= 0x12
REQ-GET-BAUDRATE_ ::= 0x1D
REQ-SET-BAUDRATE_ ::= 0x1E

MHS-DTR_ ::= 0x01
MHS-RTS_ ::= 0x02
MHS-DTR-MASK_ ::= 0x100
MHS-RTS-MASK_ ::= 0x200

MDMSTS-CTS_ ::= 0x10
MDMSTS-DSR_ ::= 0x20
MDMSTS-RI_ ::= 0x40
MDMSTS-DCD_ ::= 0x80

// Both directions, transmit and receive queues, as Linux does.
PURGE-ALL_ ::= 0x0F

VENDOR-INTERFACE_ ::= usb.REQUEST-TYPE-VENDOR | usb.REQUEST-RECIPIENT-INTERFACE

/**
A serial port on a Silicon Labs CP210x USB-UART bridge.

The requests are the ones documented in AN571. The request recipient is an
  interface, so `wIndex` carries the interface number; the CP2105 and CP2108
  have more than one.
*/
class Cp210x extends PortBase_:
  /**
  The vendor and product ids this driver handles: CP2102, CP2102N, CP2104
    and CP2109 (0xEA60), CP2105 (0xEA70) and CP2108 (0xEA71).
  */
  static IDS ::= [
    [0x10C4, 0xEA60],
    [0x10C4, 0xEA70],
    [0x10C4, 0xEA71],
  ]

  baud-rate_/int := 0

  /** Whether $device is a bridge this driver handles. */
  static matches device/usb.Device -> bool:
    return IDS.any: | ids/List | ids[0] == device.vendor-id and ids[1] == device.product-id

  /**
  Opens interface $interface-number of the CP210x $device at $baud-rate.

  Claims the interface and discards whatever the chip has buffered.
  DTR and RTS are left deasserted, since devkits wire them to EN and IO0.

  The $data-bits (5 to 8), $parity (one of the Port.PARITY- constants) and
    $stop-bits (1 or 2) configure the line.

  Received data is buffered in the background, in $read-buffer-size bytes;
    see `usb.Device.in-stream`.

  With `--no-check-ids` the vendor and product ids are not checked, for clones
    with other ids. The interface must then have the CP210x shape: vendor
    class, a bulk IN and a bulk OUT endpoint.
  */
  constructor device/usb.Device
      --baud-rate/int=115200
      --data-bits/int=8
      --parity/int=Port.PARITY-NONE
      --stop-bits/int=1
      --read-buffer-size/int=4096
      --interface-number/int=0
      --check-ids/bool=true:
    if check-ids and not matches device: throw "not a CP210x: $device"
    descriptors := device.interfaces.filter: | descriptor/usb.InterfaceDescriptor |
      descriptor.number == interface-number
    if descriptors.is-empty: throw "no interface $interface-number: $device"
    descriptor/usb.InterfaceDescriptor := descriptors[0]
    if not check-ids:
      bulk := descriptor.endpoints.filter: | endpoint/usb.EndpointDescriptor | endpoint.is-bulk
      if descriptor.class-code != 0xFF or descriptor.endpoints.size != 2 or bulk.size != 2:
        throw "not a CP210x interface: $descriptor"
    line := line-control --data-bits=data-bits --parity=parity --stop-bits=stop-bits
    super device descriptor --read-buffer-size=read-buffer-size
    start_:
      control-out_ REQ-IFC-ENABLE_ 1
      this.baud-rate = baud-rate
      control-out_ REQ-SET-LINE-CTL_ line
      write-modem-control_
      purge

  baud-rate -> int: return baud-rate_

  /**
  Changes the line to $new-rate baud.

  The chip rounds the rate to what it can do and rejects nothing;
    $read-baud-rate tells what it settled on.
  */
  baud-rate= new-rate/int -> none:
    data := ByteArray 4
    io.LITTLE-ENDIAN.put-uint32 data 0 new-rate
    device_.control-out --request-type=VENDOR-INTERFACE_ --request=REQ-SET-BAUDRATE_ --index=interface_.number --data=data
    baud-rate_ = new-rate

  /** Reads back the baud rate the bridge actually uses. */
  read-baud-rate -> int:
    data := device_.control-in --request-type=VENDOR-INTERFACE_ --request=REQ-GET-BAUDRATE_ --index=interface_.number --length=4
    if data.size < 4: throw "SHORT_RESPONSE"
    return io.LITTLE-ENDIAN.uint32 data 0

  /** Discards the data the chip has buffered in either direction. */
  purge -> none:
    control-out_ REQ-PURGE_ PURGE-ALL_

  write-modem-control_ -> none:
    value := (dtr_ ? MHS-DTR_ : 0) | (rts_ ? MHS-RTS_ : 0) | MHS-DTR-MASK_ | MHS-RTS-MASK_
    control-out_ REQ-SET-MHS_ value

  close-chip_ -> none:
    // Linux purges before disabling; some CP2108 hang otherwise.
    purge
    control-out_ REQ-IFC-ENABLE_ 0

  /** See $Port.modem-status. */
  modem-status -> int:
    data := device_.control-in --request-type=VENDOR-INTERFACE_ --request=REQ-GET-MDMSTS_ --index=interface_.number --length=1
    if data.size < 1: throw "SHORT_RESPONSE"
    status := data[0]
    result := 0
    if status & MDMSTS-CTS_ != 0: result |= Port.MODEM-CTS
    if status & MDMSTS-DSR_ != 0: result |= Port.MODEM-DSR
    if status & MDMSTS-RI_ != 0: result |= Port.MODEM-RI
    if status & MDMSTS-DCD_ != 0: result |= Port.MODEM-DCD
    return result

  control-out_ request/int value/int -> none:
    device_.control-out --request-type=VENDOR-INTERFACE_ --request=request --value=value --index=interface_.number

  /**
  Computes the `SET_LINE_CTL` value for the given $data-bits, $parity and
    $stop-bits.
  */
  static line-control --data-bits/int --parity/int --stop-bits/int -> int:
    if not 5 <= data-bits <= 8: throw "INVALID_ARGUMENT"
    if not Port.PARITY-NONE <= parity <= Port.PARITY-SPACE: throw "INVALID_ARGUMENT"
    // 0 is one stop bit, 2 is two.
    if stop-bits != 1 and stop-bits != 2: throw "INVALID_ARGUMENT"
    stop := stop-bits == 1 ? 0 : 2
    // The parity encoding matches the Port.PARITY- constants.
    return data-bits << 8 | parity << 4 | stop
