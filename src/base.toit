// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import io
import usb.host as usb
import .port

/**
The transport shared by the bridge drivers: one claimed interface with a
  bulk IN and a bulk OUT endpoint carrying the serial data.

Subclasses configure the chip and implement the control requests.
*/
abstract class PortBase_ extends Object with io.InMixin io.OutMixin implements Port:
  device_/usb.Device
  interface_/usb.InterfaceDescriptor
  in-endpoint_/usb.EndpointDescriptor
  out-endpoint_/usb.EndpointDescriptor
  read-buffer-size_/int
  // Reads the bridge in the background, so data that arrives while the
  //   program is busy waits here instead of overflowing the bridge. Null
  //   until $start_.
  in-stream_/usb.InStream? := null
  dtr_/bool := false
  rts_/bool := false
  is-closed_/bool := false

  /**
  Takes the bulk endpoints of the $interface_ on the $device_ and claims
    the interface. Subclasses then call $start_.
  */
  constructor .device_ .interface_ --read-buffer-size/int:
    read-buffer-size_ = read-buffer-size
    ins := interface_.endpoints.filter: | endpoint/usb.EndpointDescriptor |
      endpoint.is-bulk and endpoint.is-in
    outs := interface_.endpoints.filter: | endpoint/usb.EndpointDescriptor |
      endpoint.is-bulk and endpoint.is-out
    if ins.is-empty or outs.is-empty: throw "no bulk endpoints: $interface_"
    in-endpoint_ = ins[0]
    out-endpoint_ = outs[0]
    device_.claim-interface interface_.number

  /**
  Configures the chip with $block, then starts reading with a buffer of
    $read-buffer-size_ bytes, so nothing received at the old settings is
    buffered. Closes the port if either throws.
  */
  start_ [block] -> none:
    is-started := false
    try:
      block.call
      in-stream_ = device_.in-stream in-endpoint_ --buffer-size=read-buffer-size_
      is-started = true
    finally:
      if not is-started: close

  is-closed -> bool: return is-closed_

  dtr -> bool: return dtr_

  rts -> bool: return rts_

  /** See $Port.set-modem-control. */
  set-modem-control --dtr/bool --rts/bool -> none:
    old-dtr := dtr_
    old-rts := rts_
    dtr_ = dtr
    rts_ = rts
    is-written := false
    try:
      write-modem-control_
      is-written = true
    finally:
      if not is-written:
        dtr_ = old-dtr
        rts_ = old-rts

  abstract baud-rate -> int

  abstract baud-rate= new-rate/int -> none

  abstract modem-status -> int

  /** Sends $dtr_ and $rts_ to the chip. */
  abstract write-modem-control_ -> none

  /** Chip specific steps of $close, before the interface is released. */
  abstract close-chip_ -> none

  /** See $Port.close. */
  close -> none:
    if is-closed_: return
    is-closed_ = true
    mark-reader-closed_
    mark-writer-closed_
    // Closing is often done in a finally after a timeout, and once the
    //   deadline has passed, catch rethrows instead of catching. The chip
    //   requests get a deadline of their own instead.
    critical-do --no-respect-deadline:
      // Wakes up a writer blocked in another task.
      catch: device_.cancel-transfer out-endpoint_
      // Wakes up a reader blocked in another task.
      if in-stream_: catch: in-stream_.close
      if not device_.is-gone:
        catch:
          with-timeout --ms=1_000:
            if dtr_ or rts_:
              dtr_ = false
              rts_ = false
              write-modem-control_
            close-chip_
      catch: device_.release-interface interface_.number

  /**
  Reads whatever the bridge has sent.

  Data that arrived before an unplug is still returned; null comes after.
  */
  read_ -> ByteArray?:
    if is-closed_: return null
    data/ByteArray? := null
    // Canceled by close, or unplugged.
    exception := catch --unwind=(: not is-closed_ and it != "USB_NO_DEVICE"):
      data = in-stream_.read
    if exception: return null
    return data

  try-write_ data/io.Data from/int to/int -> int:
    if is-closed_: throw "WRITER_CLOSED"
    // One native buffer per call; the writer loops for the rest.
    to = min to (from + 512)
    bytes := data is ByteArray ? (data as ByteArray)[from..to] : (ByteArray.from data from to)
    // Canceled by close.
    exception := catch --unwind=(: not is-closed_):
      device_.transfer-out out-endpoint_ bytes
    if exception: throw "WRITER_CLOSED"
    return to - from
