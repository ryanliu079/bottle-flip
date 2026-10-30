#!/usr/bin/env python3
"""Create the game's original short marimba-style success cue, with no samples."""
from array import array
from pathlib import Path
import math
import random
import sys
import wave

RATE = 48_000
DURATION = 1.40
FRAMES = round(RATE * DURATION)


def render():
    dry = [0.0] * FRAMES
    randomizer = random.Random(120)
    # A compact C-major rise followed by a gentle, resolving chord.
    notes = [(0.00, 72, 0.70), (0.11, 76, 0.67), (0.22, 79, 0.67),
             (0.36, 84, 0.65), (0.36, 72, 0.33), (0.36, 76, 0.25)]
    modes = [(1.0, 1.0, 0.32), (2.0, 0.18, 0.16), (3.99, 0.18, 0.09),
             (5.0, 0.035, 0.07), (9.97, 0.014, 0.035)]
    for onset, pitch, gain in notes:
        frequency = 440 * 2 ** ((pitch - 69) / 12)
        start = round(onset * RATE)
        for index in range(start, FRAMES):
            t = (index - start) / RATE
            attack = 1 - math.exp(-t / 0.0025)
            body = sum(level * math.sin(math.tau * frequency * ratio * t)
                       * math.exp(-t / decay) for ratio, level, decay in modes)
            # A quiet rounded mallet transient, rather than an explosive pop.
            tap = randomizer.uniform(-1, 1) * 0.045 * math.exp(-t / 0.009)
            dry[index] += gain * attack * (body + tap)
    stereo = []
    # Low-level early room reflections; no long crowd/noise tail on each retry.
    for index in range(FRAMES):
        left = dry[index]
        right = dry[index]
        for delay, gain in [(0.041, 0.085), (0.079, 0.050), (0.127, 0.025)]:
            earlier = index - round(delay * RATE)
            if earlier >= 0:
                left += dry[earlier] * gain
            earlier = index - round((delay + 0.012) * RATE)
            if earlier >= 0:
                right += dry[earlier] * gain
        fade = min(1.0, index / (RATE * 0.004), (FRAMES - 1 - index) / (RATE * 0.075))
        stereo.extend((left * fade, right * fade))
    peak = max(abs(value) for value in stereo)
    pcm = array('h', (round(value / peak * 0.76 * 32767) for value in stereo))
    if sys.byteorder != 'little':
        pcm.byteswap()
    return pcm


if __name__ == '__main__':
    destination = Path(__file__).resolve().parents[1] / 'BottleFlip/App/Sounds/Celebration.wav'
    with wave.open(str(destination), 'wb') as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(render().tobytes())
    print(f'Wrote {destination}: {DURATION:.2f}s stereo 48 kHz PCM, peak 76%')
