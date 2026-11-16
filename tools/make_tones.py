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
# Static: every right swipe.
save("zap", zap())
print("Done.")
