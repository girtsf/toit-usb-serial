// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/**
Driver for the Silicon Labs CP210x USB-UART bridges.

The requests are the ones documented in AN571. The request recipient is an
  interface, so `wIndex` carries the interface number; the CP2105 and CP2108
  have more than one.
*/

import io
import usb.host as usb
import .port

/** The Silicon Labs vendor id. */
VID ::= 0x10C4
/** The product ids this driver handles: CP2102/CP2109, CP2105 and CP2108. */
PIDS ::= [0xEA60, 0xEA70, 0xEA71]

REQ-IFC-ENABLE_ ::= 0x00
REQ-SET-LINE-CTL_ ::= 0x03
REQ-SET-MHS_ ::= 0x07
REQ-GET-MDMSTS_ ::= 0x08
REQ-PURGE_ ::= 0x12
REQ-SET-FLOW_ ::= 0x13
REQ-GET-BAUDRATE_ ::= 0x1D
REQ-SET-BAUDRATE_ ::= 0x1E

MHS-DTR_ ::= 0x01
MHS-RTS_ ::= 0x02
MHS-DTR-MASK_ ::= 0x100
MHS-RTS-MASK_ ::= 0x200

PURGE-TX_ ::= 0x01
PURGE-RX_ ::= 0x02

VENDOR-INTERFACE_ ::= usb.TYPE-VENDOR | usb.RECIPIENT-INTERFACE

/** A serial port on a CP210x bridge. */
class Cp210x extends Object with io.InMixin io.OutMixin implements Port:
  device_/usb.Device
  interface_/int
  in-endpoint_/int
  out-endpoint_/int
  in-max_/int
  dtr_/bool := false
  rts_/bool := false
  is-closed_/bool := false

  /** Whether $device is a bridge this driver handles. */
  static matches device/usb.Device -> bool:
    return device.vid == VID and PIDS.contains device.pid

  /**
  Opens interface $interface-number of the CP210x $device at $baud-rate, 8N1.

  Claims the interface and discards whatever the chip has buffered.
  DTR and RTS are left deasserted, since devkits wire them to EN and IO0.

  With `--no-check-ids` the vendor and product ids are not checked, for clones
    with other ids. The interface must then have the CP210x shape: vendor
    class, a bulk IN and a bulk OUT endpoint.
  */
  constructor device/usb.Device --baud-rate/int=115200 --interface-number/int=0 --check-ids/bool=true:
    if check-ids and not matches device: throw "not a CP210x: $device"
    device_ = device
    interface_ = interface-number
    iface := device.interfaces.filter: it.number == interface-number
    if iface.is-empty: throw "no interface $interface-number: $device"
    in := iface[0].endpoints.filter: it.is-bulk and it.is-in
    out := iface[0].endpoints.filter: it.is-bulk and not it.is-in
    if in.is-empty or out.is-empty: throw "no bulk endpoints: $iface[0]"
    if not check-ids:
      if iface[0].class-code != 0xFF or iface[0].endpoints.size != 2 or in.size != 1 or out.size != 1:
        throw "not a CP210x interface: $iface[0]"
    in-endpoint_ = in[0].address
    out-endpoint_ = out[0].address
    in-max_ = in[0].max-packet-size
    device.claim-interface interface-number

    control-out_ REQ-IFC-ENABLE_ 1
    set-baud-rate baud-rate
    // 8 data bits, no parity, 1 stop bit.
    control-out_ REQ-SET-LINE-CTL_ (8 << 8)
    purge

  is-closed -> bool: return is-closed_

  /** See $Port.close. */
  close -> none:
    if is-closed_: return
    is-closed_ = true
    mark-reader-closed_
    mark-writer-closed_
    catch: control-out_ REQ-IFC-ENABLE_ 0
    catch: device_.release-interface interface_

  /** Changes the line to $baud-rate. */
  set-baud-rate baud-rate/int -> none:
    data := ByteArray 4
    io.LITTLE-ENDIAN.put-uint32 data 0 baud-rate
    device_.control-out --request-type=VENDOR-INTERFACE_ --request=REQ-SET-BAUDRATE_ --index=interface_ --data=data

  /** The baud rate the bridge actually uses, read back from the chip. */
  baud-rate -> int:
    data := device_.control-in --request-type=VENDOR-INTERFACE_ --request=REQ-GET-BAUDRATE_ --index=interface_ --length=4
    return io.LITTLE-ENDIAN.uint32 data 0

  /** Discards the data the chip has buffered in either direction. */
  purge -> none:
    control-out_ REQ-PURGE_ (PURGE-TX_ | PURGE-RX_)

  dtr -> bool: return dtr_

  rts -> bool: return rts_

  /** See $Port.set-modem-control. */
  set-modem-control --dtr/bool=dtr_ --rts/bool=rts_ -> none:
    dtr_ = dtr
    rts_ = rts
    value := (dtr ? MHS-DTR_ : 0) | (rts ? MHS-RTS_ : 0) | MHS-DTR-MASK_ | MHS-RTS-MASK_
    control-out_ REQ-SET-MHS_ value

  /** The modem status: DTR in bit 0, RTS in 1, CTS in 4, DSR in 5, RI in 6, DCD in 7. */
  modem-status -> int:
    data := device_.control-in --request-type=VENDOR-INTERFACE_ --request=REQ-GET-MDMSTS_ --index=interface_ --length=1
    return data[0]

  control-out_ request/int value/int -> none:
    device_.control-out --request-type=VENDOR-INTERFACE_ --request=request --value=value --index=interface_

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
