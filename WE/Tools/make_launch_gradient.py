#!/usr/bin/env python3
"""Render the launch gradient to a PNG.

The launch screen is a storyboard, and a storyboard cannot express a gradient
— so it ships as an image. The collapse's first frame draws the *same* image
rather than a computed LinearGradient, which is what makes the handoff from
the OS launch screen seamless by construction instead of by matching five
stops and an angle across every device.

Kept in the repo because the alternative is reverse-engineering a 118 degree
sweep out of a PNG the next time a stop moves.

    python3 Tools/make_launch_gradient.py

Standard library only: no Pillow, no new dependency for a build asset.
"""

from __future__ import annotations

import math
import pathlib
import struct
import zlib

# The direction the sweep runs, corner to corner rather than horizontally, so
# the disc the collapse ends on lands on a diagonal blend and not a flat band.
ANGLE_DEGREES = 118.0

# From the spec, in CSS gradient order.
STOPS: list[tuple[float, tuple[int, int, int]]] = [
    (0.06, (0xD9, 0x8E, 0x5A)),  # warm      — FieldSwatch.clay
    (0.34, (0xC4, 0x92, 0x6F)),  # warm-mid
    (0.50, (0x9C, 0x9A, 0x96)),  # meld
    (0.66, (0x88, 0xA2, 0xAE)),  # cool-mid
    (0.94, (0x79, 0xA6, 0xB8)),  # cool      — FieldSwatch.slate
]

# Square, so aspectFill crops rather than distorts on any device.
SIZE = 2048

OUTPUT = (
    pathlib.Path(__file__).resolve().parent.parent
    / "WE/Assets.xcassets/WELaunchGradient.imageset/WELaunchGradient.png"
)


def colour_at(t: float) -> tuple[int, int, int]:
    """The gradient colour at position `t`, clamped outside the stop range."""
    if t <= STOPS[0][0]:
        return STOPS[0][1]
    if t >= STOPS[-1][0]:
        return STOPS[-1][1]

    for (t0, c0), (t1, c1) in zip(STOPS, STOPS[1:]):
        if t0 <= t <= t1:
            span = t1 - t0
            k = 0.0 if span == 0 else (t - t0) / span
            return (
                round(c0[0] + (c1[0] - c0[0]) * k),
                round(c0[1] + (c1[1] - c0[1]) * k),
                round(c0[2] + (c1[2] - c0[2]) * k),
            )
    return STOPS[-1][1]


def render() -> bytes:
    """Raw RGB rows, projected along the gradient axis.

    CSS measures a linear gradient along the axis through the centre, with 0
    and 1 at the perpendicular projections of the two corners — so the
    projection is normalised against that length rather than the image width.
    """
    theta = math.radians(ANGLE_DEGREES)
    # CSS angles run clockwise from "to top"; this is that, in image space
    # where y grows downward.
    dx, dy = math.sin(theta), -math.cos(theta)

    half = SIZE / 2
    extent = abs(half * dx) + abs(half * dy)

    # One row of the ramp is enough to look up from: quantise the projection
    # into it rather than recomputing the stop search per pixel.
    ramp = [colour_at(i / (SIZE * 2 - 1)) for i in range(SIZE * 2)]

    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)  # PNG per-row filter: none
        py = y - half + 0.5
        for x in range(SIZE):
            px = x - half + 0.5
            t = ((px * dx + py * dy) / extent + 1) / 2
            index = min(len(ramp) - 1, max(0, round(t * (len(ramp) - 1))))
            rows.extend(ramp[index])
    return bytes(rows)


def png(raw: bytes) -> bytes:
    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def main() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(png(render()))
    print(f"wrote {OUTPUT} ({OUTPUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
