"""Records every Host line, and the creatures' voices, with Kokoro (free, Apache 2.0, runs on your computer).

Setup (once):
    python3 -m venv tools/.venv && tools/.venv/bin/pip install kokoro-onnx soundfile
    mkdir -p tools/models && cd tools/models
    curl -LO https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx
    curl -LO https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin
Run:
    tools/.venv/bin/python tools/make_voices.py            # only lines that don't have a recording yet
    tools/.venv/bin/python tools/make_voices.py --all      # redo everything
    tools/.venv/bin/python tools/make_voices.py george     # just one Host
The line list (tools/host_lines.json) comes from the game: in Packages/HallwayCore run
    DUMP_PATH=../../tools/host_lines.json swift test --filter testDumpScript
Needs ffmpeg.
"""
import json, os, subprocess, sys
import soundfile as sf
from kokoro_onnx import Kokoro

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MODELS = os.environ.get("KOKORO_MODELS", os.path.join(HERE, "models"))
OUT = os.path.join(ROOT, "App", "Voices")
ALL = "--all" in sys.argv

WORDS = {"en": ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"],
         "pt": ["um", "dois", "três", "quatro", "cinco", "seis", "sete", "oito", "nove", "dez"]}
# The Counter: a slow, low whisper close to your ear. The Mimic: three friendly-sounding voices.
# Each in English (sfx_<name>) and Portuguese (sfx_pt_<name>).
CREATURES = []
ECHO_WORDS = {"en": ["left", "right", "up", "down", "knock"], "pt": ["esquerda", "direita", "cima", "baixo", "batida"]}
ECHO_MOVES = ["left", "right", "up", "down", "tap"]
for lang, prefix, counter, voices, phrases in [
    ("en-us", "sfx_", "am_onyx", ["af_nicole", "am_echo", "af_sky"], ["Over here!", "Hello? Is someone there?", "Help me. Please."]),
    ("pt-br", "sfx_pt_", "pm_alex", ["pf_dora", "pm_santa", "pf_dora"], ["Aqui!", "Oi? Tem alguém aí?", "Me ajuda. Por favor."]),
]:
    words = WORDS["en" if lang == "en-us" else "pt"]
    CREATURES += [(f"{prefix}count{n}", words[n - 1] + ".", counter, 0.8, lang, "counter") for n in range(1, 11)]
    CREATURES += [(f"{prefix}mimic_voice{i + 1}", phrases[i], voices[i], 1.0, lang, "mimic") for i in range(3)]
    # The Twins: the same girl's voice says "left" or "right" (and two of them whisper through the door).
    twin = "af_sky" if lang == "en-us" else "pf_dora"
    words = ("Left!", "Right!", "This way. No, this way.") if lang == "en-us" else ("Esquerda!", "Direita!", "Por aqui. Não, por aqui.")
    CREATURES += [(f"{prefix}twin_left", words[0], twin, 1.0, lang, "mimic"),
                  (f"{prefix}twin_right", words[1], twin, 1.0, lang, "mimic"),
                  (f"{prefix}hint_twins", words[2], twin, 0.9, lang, "whisper")]
    # The Echo's whispers: the name of each move.
    whisperer = "af_nicole" if lang == "en-us" else "pf_dora"
    CREATURES += [(f"{prefix}echo_say_{m}", w + ".", whisperer, 0.9, lang, "whisper")
                  for m, w in zip(ECHO_MOVES, ECHO_WORDS["en" if lang == "en-us" else "pt"])]

TRIM = ("silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
        "silenceremove=start_periods=1:start_threshold=-45dB,areverse")
FX = {
    "host": "",
    # Lower, breathy and echoing.
    "counter": "asetrate=24000*0.82,aresample=24000,highpass=f=120,aecho=0.8:0.6:60|140:0.35|0.2,",
    "mimic": "",
    # Soft and close, a little echo, quieter than the music box.
    "whisper": "highpass=f=200,aecho=0.8:0.5:40:0.25,volume=0.8,",
}

kokoro = Kokoro(os.path.join(MODELS, "kokoro-v1.0.onnx"), os.path.join(MODELS, "voices-v1.0.bin"))
os.makedirs(OUT, exist_ok=True)
raw = os.path.join(HERE, "_raw.wav")


def record(name, text, voice, speed, lang, fx, out_dir=OUT):
    target = os.path.join(out_dir, name + ".m4a")
    if os.path.exists(target) and not ALL:
        return False
    audio, rate = kokoro.create(text, voice=voice, speed=speed, lang=lang)
    sf.write(raw, audio, rate)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", raw, "-af", FX[fx] + TRIM + ",loudnorm=I=-16:TP=-1.5,aresample=44100",
                    "-ac", "1", "-c:a", "aac", "-b:a", "64k", target], check=True)
    return True


hosts = json.load(open(os.path.join(HERE, "host_lines.json")))
only = [a for a in sys.argv[1:] if not a.startswith("--")]   # e.g. "george emma": just those Hosts
made = 0
for h in hosts:
    if only and h["host"] not in only:
        continue
    if h["voice"].startswith("chatterbox:"):
        continue   # recorded by make_voices_chatterbox.py
    for line_id, text in h["lines"].items():
        made += record(f"v_{h['host']}_{line_id}", text, h["voice"], h["speed"], h["lang"], "host")
sounds = os.path.join(ROOT, "App", "Sounds")
os.makedirs(sounds, exist_ok=True)
for name, text, voice, speed, lang, fx in CREATURES:
    made += record(name, text, voice, speed, lang, fx, sounds)
if os.path.exists(raw):
    os.remove(raw)
print(f"{made} new recordings ({len(hosts)} Hosts)")
