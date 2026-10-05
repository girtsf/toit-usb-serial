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
  dtr_/bool := false
  rts_/bool := false
  is-closed_/bool := false

  /**
  Takes the bulk endpoints of the $interface_ on the $device_ and claims the
    interface.
  */
  constructor .device_ .interface_:
    in := interface_.endpoints.filter: | endpoint/usb.EndpointDescriptor |
      endpoint.is-bulk and endpoint.is-in
    out := interface_.endpoints.filter: | endpoint/usb.EndpointDescriptor |
      endpoint.is-bulk and endpoint.is-out
    if in.is-empty or out.is-empty: throw "no bulk endpoints: $interface_"
    in-endpoint_ = in[0]
    out-endpoint_ = out[0]
    device_.claim-interface interface_.number

  is-closed -> bool: return is-closed_

  dtr -> bool: return dtr_

  rts -> bool: return rts_

  /** See $Port.set-modem-control. */
  set-modem-control --dtr/bool=dtr_ --rts/bool=rts_ -> none:
    dtr_ = dtr
    rts_ = rts
    write-modem-control_

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
    // Wakes up a reader blocked in another task; read_ then sees the flag.
    catch: device_.cancel-transfer in-endpoint_
    mark-reader-closed_
    mark-writer-closed_
    if not device_.is-gone:
      if dtr_ or rts_:
        dtr_ = false
        rts_ = false
        catch: write-modem-control_
      catch: close-chip_
    catch: device_.release-interface interface_.number

  /** Reads whatever the bridge has, at most one transfer. */
  read_ -> ByteArray?:
    max := in-endpoint_.max-packet-size * (512 / in-endpoint_.max-packet-size)
    while true:
      if is-closed_ or device_.is-gone: return null
      data/ByteArray? := null
      exception := catch:
        data = device_.transfer-in in-endpoint_ --max=max
      if exception:
        // Canceled by close, or unplugged.
        if is-closed_ or exception == "USB_NO_DEVICE": return null
        throw exception
      if data.size > 0: return data

  try-write_ data/io.Data from/int to/int -> int:
    if is-closed_: throw "CLOSED"
    // One native buffer per call; the writer loops for the rest.
    to = min to (from + 512)
    bytes := data is ByteArray ? (data as ByteArray)[from..to] : (ByteArray.from data from to)
    device_.transfer-out out-endpoint_ bytes
    return to - from
