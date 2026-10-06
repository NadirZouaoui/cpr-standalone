"""Generates audio/cues/ambulance_arrive.wav — the HANDOVER beat's siren.

THIS IS A PLACEHOLDER, NOT A FINAL ASSET. It is synthesised from sine waves by
the standard library so the last beat of the run can be heard in context before
anyone commits to a recording. It should be replaced by a real siren recording
— ideally an Australian ambulance, since that is the service the trainee is
handing over to — and this file kept only as the spec that replacement is
measured against. Same standing as tools/gen_breathing_negative.py, which is
the pattern this follows.

Stdlib only; run from the project root:

    python tools/gen_ambulance_arrive.py

WHAT IT IS AND IS NOT. This fires once, when the casualty is in the recovery
position and the injury survey is done: the ambulance is arriving and the
exercise is over. It is the full stop on the run, so it has to read as relief
rather than as alarm — the trainee has finished, and a siren that sounds like
an emergency starting would be the wrong claim at the wrong moment.

So: a hi-lo two-tone, the shape used across Europe and Australia, arriving from
a distance. The approach is carried by three things at once, because amplitude
alone reads as a volume knob rather than as a vehicle:

  * loudness rises from nearly nothing to full over the whole cue;
  * the low-pass proxy (a first-order one-pole filter) opens as it nears, so
    the distant part of the cue is dull and the near part is bright — distance
    eats high frequencies long before it eats volume;
  * the pitch is a touch high on approach and settles back as it arrives, which
    is the Doppler shift, understated on purpose. A full Doppler sweep reads as
    a vehicle passing by and not stopping, which is the opposite of what this
    beat means.

It does not end in a squeal of brakes or a door slam. The run's last sound
should leave room for the debrief, not compete with it.
"""

import math
import os
import struct
import wave

RATE = 44100
TOTAL_S = 6.5

## Peak amplitude, at the very end. Matched to breathing_negative.wav's
## restraint: this plays under a centre message the trainee is reading.
AMPLITUDE = 0.30

## The two-tone pair, in Hz, at the point the vehicle has arrived. A perfect
## fourth apart, which is the interval a European hi-lo actually uses.
TONE_HIGH = 660.0
TONE_LOW = 495.0

## Seconds per note. Just under half a second is the real cadence.
NOTE_S = 0.45

## Doppler: the tone starts this much sharp and settles to true. 2% is about
## 35 Hz at 660 — audible as movement, well short of a fly-past.
DOPPLER_START = 1.02

## The one-pole low-pass coefficient at the two extremes. Small = dull/far.
CUTOFF_FAR = 0.06
CUTOFF_NEAR = 0.55

## Loudness at the start, as a fraction of AMPLITUDE. Not zero: a cue that
## fades up from true silence has no attack and reads as a fault.
LEVEL_FAR = 0.04

## The last stretch is held at full rather than still rising — the vehicle has
## stopped outside, and a cue still growing at the cut is a cue that got
## truncated.
ARRIVED_AT = 0.82


def approach(t):
    """0 at the start, 1 once it has arrived. Eased, not linear: a vehicle
    closes the last of the distance far faster than the first of it."""
    x = min(1.0, (t / TOTAL_S) / ARRIVED_AT)
    return x * x


def main():
    out_dir = os.path.join(os.path.dirname(__file__), "..", "audio", "cues")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.normpath(os.path.join(out_dir, "ambulance_arrive.wav"))

    frames = bytearray()
    phase = 0.0
    filtered = 0.0
    total = int(TOTAL_S * RATE)

    for i in range(total):
        t = i / RATE
        near = approach(t)

        # Which half of the two-tone we are in.
        base = TONE_HIGH if int(t / NOTE_S) % 2 == 0 else TONE_LOW
        freq = base * (DOPPLER_START - (DOPPLER_START - 1.0) * near)

        # Phase accumulation rather than sin(2*pi*f*t): the frequency changes
        # every sample, and the direct form would step the phase discontinuously
        # at every change and click.
        phase += 2.0 * math.pi * freq / RATE
        if phase > 2.0 * math.pi:
            phase -= 2.0 * math.pi

        # A little third harmonic so it is a horn rather than a test tone.
        raw = math.sin(phase) + 0.22 * math.sin(3.0 * phase)

        cutoff = CUTOFF_FAR + (CUTOFF_NEAR - CUTOFF_FAR) * near
        filtered += cutoff * (raw - filtered)

        level = LEVEL_FAR + (1.0 - LEVEL_FAR) * near
        # Fade the last 150 ms so the file does not end on a discontinuity.
        tail = min(1.0, (TOTAL_S - t) / 0.15)

        sample = max(-1.0, min(1.0, filtered * 0.7)) * AMPLITUDE * level * tail
        frames += struct.pack("<h", int(sample * 32767.0))

    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(frames))
    print("wrote %s (%.2f s, %d bytes)" % (path, TOTAL_S, len(frames)))


if __name__ == "__main__":
    main()
