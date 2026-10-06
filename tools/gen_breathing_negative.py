"""Generates audio/cues/breathing_negative.wav — the breathing-check result tone.

A placeholder to the spec agreed for CPR_CONTRACT.md §9 seam 4, so the cue can
be heard in context before a final recording is committed to. Stdlib only; run
from the project root:

    python tools/gen_breathing_negative.py

WHAT IT IS AND IS NOT. This fires when the 5 s hold completes and the answer is
"not breathing" — a clinical finding, not a mark against the trainee, who did
exactly the right thing. So: a falling two-note sine figure, soft attack, long
release, quiet. Not a buzzer, and nothing with the shape of a game "wrong"
sting — §4.4 forbids a negative tone for wrong pad sites, and an error-shaped
sound here would be read as one when it appears nowhere else.
"""

import math
import os
import struct
import wave

RATE = 44100
AMPLITUDE = 0.28  # peak, well under the AED voice lines

# (frequency Hz, start s, duration s, release s)
# F3 -> C#3: a falling minor third, the second note lower and longer.
NOTES = [
    (174.61, 0.00, 0.30, 0.22),
    (138.59, 0.26, 0.62, 0.50),
]
TOTAL_S = 0.95

ATTACK_S = 0.025  # soft enough that there is no click on the transient


def envelope(t, duration, release):
    """Soft attack, flat-ish body, long exponential release to silence."""
    if t < 0.0 or t > duration:
        return 0.0
    a = min(1.0, t / ATTACK_S)
    body = duration - release
    if t <= body:
        return a
    return a * math.exp(-4.0 * (t - body) / release)


def main():
    out_dir = os.path.join(os.path.dirname(__file__), "..", "audio", "cues")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.normpath(os.path.join(out_dir, "breathing_negative.wav"))

    frames = bytearray()
    for i in range(int(TOTAL_S * RATE)):
        t = i / RATE
        sample = 0.0
        for freq, start, duration, release in NOTES:
            sample += math.sin(2.0 * math.pi * freq * (t - start)) * envelope(
                t - start, duration, release
            )
        # Two overlapping notes at full amplitude would clip on the crossover.
        sample = max(-1.0, min(1.0, sample * 0.6)) * AMPLITUDE
        frames += struct.pack("<h", int(sample * 32767.0))

    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(frames))
    print("wrote %s (%.2f s, %d bytes)" % (path, TOTAL_S, len(frames)))


if __name__ == "__main__":
    main()
