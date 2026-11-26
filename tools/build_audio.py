"""Generate original Track Playground sound effects using only Python's stdlib.

Run from any directory. No recordings, downloads or third-party assets are used.
Loops are periodic; transients have short fades to avoid clicks.
"""

import math
from pathlib import Path
import random
import struct
import wave

RATE = 24000
TAU = math.tau
OUT = Path(__file__).resolve().parents[1] / "assets" / "audio"


def tone(t, frequency):
    return math.sin(TAU * frequency * t)


def write(name, duration, sample, peak=0.65, loop=False):
    rng = random.Random(418 + sum(map(ord, name)))
    count = round(duration * RATE)
    values = []
    low = 0.0
    for i in range(count):
        t = i / RATE
        noise = rng.uniform(-1, 1)
        low += 0.16 * (noise - low)
        value = sample(t, noise, low)
        if not loop:
            value *= min(1, t / 0.006, (duration - t) / 0.035)
        values.append(value)
    if loop:
        # Blend the last 20 ms into an extra period's beginning. This preserves
        # the rhythm and brings the noisy component smoothly across the seam.
        fade = int(RATE * 0.02)
        for i in range(fade):
            weight = (i + 1) / fade
            values[count - fade + i] = (
                values[count - fade + i] * (1 - weight)
                + values[i] * weight
            )
        values = values[fade:]
    scale = peak / max(max(abs(v) for v in values), 0.001)
    pcm = b"".join(struct.pack("<h", round(v * scale * 32767)) for v in values)
    with wave.open(str(OUT / (name + ".wav")), "wb") as stream:
        stream.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        stream.writeframes(pcm)
    print(f"{name}: {len(values) / RATE:.2f}s")


def strike(t, n, pitches, decay=30):
    return (sum(tone(t, p) / (i + 1) for i, p in enumerate(pitches))
            + n * 0.18) * math.exp(-t * decay)


def pulse(t, start, n, pitches, decay=35):
    return strike(t - start, n, pitches, decay) if t >= start else 0


def rolling(t, n, low):
    # Two wheelsets cross each rail joint, over a soft low-frequency rumble.
    phase = t % 0.8
    return (low * 0.6 + tone(t, 52) * 0.035
            + pulse(phase, 0.0, n, [170, 520, 980], 65) * 0.42
            + pulse(phase, 0.13, n, [150, 460, 850], 55) * 0.34)


def steam(t, n, low):
    phase = t % 0.25
    envelope = (1 - math.exp(-phase * 350)) * math.exp(-phase * 24)
    return envelope * (low * 1.6 + n * 0.25 + tone(t, 90) * 0.1)


def horn(t, n, low):
    envelope = min(1, t / 0.12) * min(1, (1.45 - t) / 0.25)
    return envelope * sum(tone(t, p) + 0.2 * tone(t, p * 2)
                          for p in [277, 349, 415]) / 3


def whistle(t, n, low):
    envelope = min(1, t / 0.18) * min(1, (1.6 - t) / 0.35)
    wobble = 0.004 * tone(t, 5)
    return envelope * (sum(tone(t + wobble / p, p) for p in [523, 659, 784])
                       / 3 + low * 0.18)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    write("click", 0.09, lambda t, n, l: strike(t, n, [900, 1350], 65), 0.32)
    write("place", 0.23, lambda t, n, l: strike(t, n, [180, 720, 1270], 25))
    write("connect", 0.34, lambda t, n, l: strike(t, n, [220, 840], 28)
          + pulse(t, 0.09, n, [380, 1200], 27))
    write("remove", 0.24, lambda t, n, l: strike(t, n, [140, 430], 19))
    write("turnout", 0.42, lambda t, n, l: l * 0.3 * math.exp(-t * 8)
          + pulse(t, 0.02, n, [190, 780], 35)
          + pulse(t, 0.22, n, [240, 980], 30))
    write("couple", 0.48, lambda t, n, l: strike(t, n, [95, 260, 830], 17)
          + pulse(t, 0.08, n, [180, 610], 22) * 0.45)
    write("alert", 0.36, lambda t, n, l: tone(t, 440)
          * (math.exp(-t * 25) + (math.exp(-(t - 0.16) * 25) if t > 0.16 else 0)), 0.4)
    write("confirm", 0.35, lambda t, n, l: tone(t, 660) * math.exp(-t * 20)
          + (tone(t - 0.10, 880) * math.exp(-(t - 0.10) * 18) if t > 0.10 else 0), 0.4)
    write("brake", 0.85, lambda t, n, l: (n * 0.18 + l * 1.1)
          * min(1, t / 0.05) * math.exp(-t * 4), 0.5)
    write("horn", 1.45, horn, 0.6)
    write("whistle", 1.6, whistle, 0.6)
    write("diesel", 2.02, lambda t, n, l: (tone(t, 48) * 0.34 + tone(t, 96) * 0.18
          + tone(t, 144) * 0.1 + l * 0.4) * (0.8 + 0.2 * tone(t, 12)), 0.55, True)
    write("electric", 2.02, lambda t, n, l: tone(t, 120) * 0.2 + tone(t, 360) * 0.08
          + tone(t, 720) * 0.035 + l * 0.2, 0.4, True)
    write("rolling", 2.42, rolling, 0.6, True)
    write("steam", 1.02, steam, 0.6, True)


if __name__ == "__main__":
    main()
