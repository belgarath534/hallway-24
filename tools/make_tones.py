"""Makes the game's synthesized sounds: the Echo's music-box notes and chimes, and Static's zap.

    python3 tools/make_tones.py        (needs numpy, soundfile and ffmpeg)
"""
import os, subprocess
import numpy as np
import soundfile as sf

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "App", "Sounds")
rng = np.random.default_rng(24)


def t(seconds):
    return np.arange(int(SR * seconds)) / SR


def bell(freq, seconds=0.9, glide=0.0):
    """A music-box note: a few harmonics with a quick attack and a long fade."""
    x = t(seconds)
    f = freq * (1 + glide * x / seconds)
    phase = 2 * np.pi * np.cumsum(f) / SR
    tone = np.sin(phase) + 0.35 * np.sin(2 * phase) + 0.15 * np.sin(3.01 * phase) + 0.08 * np.sin(4.2 * phase)
    env = (1 - np.exp(-x * 400)) * np.exp(-x * 4.5)
    return tone * env


def knock(seconds=0.25):
    """A wooden knock: a short, dull thump."""
    x = t(seconds)
    body = np.sin(2 * np.pi * 180 * x) * np.exp(-x * 30)
    click = rng.standard_normal(len(x)) * np.exp(-x * 120) * 0.4
    return body + click


def seq(notes, gap):
    """Notes one after another, overlapping their tails."""
    total = int(SR * (gap * (len(notes) - 1))) + max(len(n) for n in notes)
    out = np.zeros(total)
    for i, n in enumerate(notes):
        start = int(SR * gap * i)
        out[start:start + len(n)] += n
    return out


def zap(seconds=0.35):
    """An electric zap: crackle plus a falling tone."""
    x = t(seconds)
    crackle = rng.standard_normal(len(x)) * (rng.random(len(x)) < 0.25)
    falling = np.sin(2 * np.pi * np.cumsum(1400 * np.exp(-x * 8) + 200) / SR)
    return (0.6 * crackle + 0.7 * falling) * np.exp(-x * 9)


def save(name, audio, gain_db=-3):
    audio = audio / (np.max(np.abs(audio)) + 1e-9) * 10 ** (gain_db / 20)
    wav = os.path.join(OUT, f"_{name}.wav")
    sf.write(wav, audio.astype(np.float32), SR)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-ac", "1", "-c:a", "aac", "-b:a", "64k",
                    os.path.join(OUT, f"sfx_{name}.m4a")], check=True)
    os.remove(wav)


C4, C5, E5, G5, C6, E6 = 261.6, 523.3, 659.3, 784.0, 1046.5, 1318.5
os.makedirs(OUT, exist_ok=True)
# The Echo's five moves. Left and right are also placed left and right in the game.
save("echo_left", bell(C5))
save("echo_right", bell(E5))
save("echo_up", bell(G5, glide=0.25))
save("echo_down", bell(C4, seconds=1.1, glide=-0.15))
save("echo_tap", knock())
save("echo_turn", seq([bell(C6, 0.7), bell(E6, 1.0)], 0.15))
# Two low notes clashing: wrong.
save("echo_wrong", seq([bell(311.1, 0.6) + bell(329.6, 0.6), bell(233.1, 0.9) + bell(246.9, 0.9)], 0.18))
save("echo_solved", seq([bell(C5, 0.6), bell(E5, 0.6), bell(G5, 0.6), bell(C6, 1.2)], 0.12))
# Through the door: a little music-box tune.
save("hint_echo", seq([bell(f, 0.8) for f in (G5, E5, C5, E5, G5, C6)], 0.28), gain_db=-6)
# The Lullaby: a soft hummed note (the game changes its pitch), and a little tune through the door.
def hum(freq, seconds=0.7):
    x = t(seconds)
    vib = 1 + 0.012 * np.sin(2 * np.pi * 5.5 * x)
    phase = 2 * np.pi * np.cumsum(freq * vib) / SR
    tone = np.sin(phase) + 0.25 * np.sin(2 * phase) + 0.08 * np.sin(3 * phase)
    env = np.minimum(1, x * 12) * np.exp(-x * 2.2)
    return tone * env


save("lullaby_note", hum(392.0))
save("hint_lullaby", seq([hum(f, 0.6) for f in (392.0, 329.6, 392.0, 293.7)], 0.5), gain_db=-8)


# The Lights: a clock tick, the power going off and coming back, and a flickering hum through the door.
def tick_sound():
    x = t(0.09)
    return (np.sin(2 * np.pi * 2400 * x) * 0.6 + rng.standard_normal(len(x)) * 0.4) * np.exp(-x * 70)


def power(up, seconds=1.2):
    x = t(seconds)
    f = 120 * (x / seconds if up else 1 - x / seconds) + 30
    hum_ = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.4 * np.sin(4 * np.pi * np.cumsum(f) / SR)
    env = (x / seconds) if up else (1 - x / seconds)
    return hum_ * env


def flicker(seconds=2.4):
    x = t(seconds)
    base = np.sin(2 * np.pi * 60 * x) + 0.5 * np.sin(2 * np.pi * 120 * x) + 0.2 * np.sin(2 * np.pi * 180 * x)
    on = (np.sin(2 * np.pi * 3.3 * x) + 0.6 * np.sin(2 * np.pi * 7.1 * x)) > -0.3
    ticks_ = np.zeros(len(x))
    for k in range(4):
        c = tick_sound()
        start = int(SR * (0.3 + k * 0.55))
        ticks_[start:start + len(c)] += c * 0.8
    return base * on * 0.5 + ticks_


save("tick", tick_sound())
save("lights_off", power(False))
save("lights_on", power(True))
save("hint_lights", flicker(), gain_db=-6)


# The Breather: a shove (a quick whoosh).
def whoosh(seconds=0.45):
    x = t(seconds)
    noise = rng.standard_normal(len(x))
    # A simple moving filter: noise brightened as it peaks.
    k = np.exp(-((x - 0.15) ** 2) / 0.008)
    return noise * k


save("shove", whoosh())


# The Sleeper: snoring (a rattly in-breath, a soft out-breath), stirring (a snort and the bed creaking),
# searching (a rustle), a note found (paper), and the old rotary phone.
def bandnoise(seconds, lo, hi):
    n = rng.standard_normal(int(SR * seconds))
    spec = np.fft.rfft(n)
    f = np.fft.rfftfreq(len(n), 1 / SR)
    spec[(f < lo) | (f > hi)] = 0
    return np.fft.irfft(spec, len(n))


def snore_sound():
    x_in = t(1.3)
    rattle = 1 + 0.8 * np.sin(2 * np.pi * 28 * x_in)
    inhale = bandnoise(1.3, 70, 700) * rattle * np.sin(np.pi * x_in / 1.3) ** 1.5
    inhale += 0.5 * np.sin(2 * np.pi * np.cumsum(55 + 10 * x_in) / SR) * rattle * np.sin(np.pi * x_in / 1.3) ** 2
    x_out = t(0.9)
    exhale = bandnoise(0.9, 150, 1200) * 0.35 * np.sin(np.pi * x_out / 0.9) ** 2
    return np.concatenate([inhale, np.zeros(int(SR * 0.1)), exhale])


def creak(seconds=0.7):
    x = t(seconds)
    f = 180 + 60 * np.sin(2 * np.pi * 1.3 * x)
    pulses = (np.sin(2 * np.pi * np.cumsum(f) / SR) > 0.95).astype(float)
    body = np.convolve(pulses, np.exp(-np.arange(400) / 60) * np.sin(np.arange(400) * 0.18), mode="same")
    return body * np.sin(np.pi * x / seconds)


def stir_sound():
    snort = bandnoise(0.35, 60, 500) * np.exp(-t(0.35) * 6) * 1.5
    return np.concatenate([snort, np.zeros(int(SR * 0.15)), creak(), np.zeros(int(SR * 0.1)), creak(0.5) * 0.6])


def rustle(seconds=0.5):
    x = t(seconds)
    grains = (rng.random(len(x)) < 0.02).astype(float) * rng.standard_normal(len(x))
    grains = np.convolve(grains, np.exp(-np.arange(200) / 25), mode="same")
    return (grains + 0.3 * bandnoise(seconds, 1500, 6000)) * np.sin(np.pi * x / seconds)


def paper():
    x = t(0.35)
    crinkle = (rng.random(len(x)) < 0.06).astype(float) * rng.standard_normal(len(x))
    return np.convolve(crinkle, np.exp(-np.arange(80) / 10), mode="same") * np.exp(-x * 5)


def click(gain=1.0):
    x = t(0.04)
    return (np.sin(2 * np.pi * 2200 * x) * 0.6 + rng.standard_normal(len(x)) * 0.5) * np.exp(-x * 160) * gain


def dial_return():
    out = np.zeros(int(SR * 0.6))
    for k in range(9):
        c = click(0.5)
        s0 = int(SR * (0.03 + k * 0.06))
        out[s0:s0 + len(c)] += c
    return out + 0.15 * bandnoise(0.6, 300, 2000) * np.sin(np.pi * t(0.6) / 0.6)


def unlock_sound():
    ring = sum(np.sin(2 * np.pi * f * t(0.9)) for f in (880, 1320)) * np.exp(-t(0.9) * 5) * 0.4
    clack = np.concatenate([click(), np.zeros(int(SR * 0.12)), click(), np.zeros(int(SR * 0.2))])
    return np.concatenate([ring, clack, bell(G5, 0.8) * 0.4])


save("snore", snore_sound())
save("hint_sleeper", np.concatenate([snore_sound(), np.zeros(int(SR * 0.3)), snore_sound()]), gain_db=-6)
save("sleeper_stir", stir_sound())
save("search", rustle())
save("note_found", paper(), gain_db=-6)
save("dial_click", click())
save("dial_return", dial_return(), gain_db=-6)
save("unlock", unlock_sound())

# Static: every right swipe.
save("zap", zap())
print("Done.")
