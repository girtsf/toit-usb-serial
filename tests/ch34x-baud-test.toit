// Checks the CH34x prescaler/divisor math against the chip's own formula.

import expect show *
import usb-serial.ch34x show Ch34x

CLOCK-RATE ::= 48_000_000

/** The rate the chip runs at for the register value $encoded. */
decode encoded/int -> float:
  div := 0x100 - (encoded >> 8)
  fact := (encoded >> 2) & 1
  ps := encoded & 0x03
  return CLOCK-RATE.to-float / ((1 << (12 - 3 * ps - fact)) * div)

check requested/int --max-error/float=0.02 -> none:
  encoded := Ch34x.divisor requested
  actual := decode encoded
  error := (actual - requested).abs / requested
  expect error <= max-error
      --message="$requested bps encoded as 0x$(%04x encoded) gives $actual bps ($(%.2f error * 100)%)"

main:
  // Every rate a CH340 is normally used at must be within 2%.
  [
    50, 75, 110, 134, 150, 300, 600, 1200, 1800, 2400, 4800, 9600, 19200,
    38400, 57600, 115200, 230400, 460800, 500_000, 921600, 1_000_000,
    1_500_000, 2_000_000, 3_000_000,
  ].do: check it

  // The encodings the Linux ch341 driver uses for the two most common rates.
  expect-equals 0xcc03 (Ch34x.divisor 115200)
  expect-equals 0xb202 (Ch34x.divisor 9600)

  // Rates that divide the clock evenly come out exact.
  expect-equals 500_000.0 (decode (Ch34x.divisor 500_000))
  expect-equals 1_000_000.0 (decode (Ch34x.divisor 1_000_000))
  expect-equals 3_000_000.0 (decode (Ch34x.divisor 3_000_000))

  // Rates outside the chip's range are clamped, not rejected.
  expect-equals (decode (Ch34x.divisor 46)) (decode (Ch34x.divisor 1))
  expect-equals (decode (Ch34x.divisor 3_000_000)) (decode (Ch34x.divisor 10_000_000))

  // The encoding never overflows the 8-bit divisor field.
  [46, 300, 115200, 3_000_000].do:
    encoded := Ch34x.divisor it
    expect 0 <= encoded <= 0xFFFF
    div := 0x100 - (encoded >> 8)
    expect 2 <= div <= 256
