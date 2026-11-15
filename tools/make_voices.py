"""Records every Host line, and the creatures' voices, with Kokoro (free, Apache 2.0, runs on your computer).

Setup (once):
    python3 -m venv tools/.venv && tools/.venv/bin/pip install kokoro-onnx soundfile
    mkdir -p tools/models && cd tools/models
    curl -LO https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx
    curl -LO https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin
Run:
    tools/.venv/bin/python tools/make_voices.py            # only lines that don't have a recording yet
    tools/.venv/bin/python tools/make_voices.py --all      # redo everything
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

# Host: Kokoro voice, speed, language.
HOSTS = {"lewis": ("bm_lewis", 0.92, "en-gb"), "heart": ("af_heart", 0.98, "en-us")}
WORDS = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
# The Counter: a slow, low whisper close to your ear. The Mimic: three friendly-sounding voices.
CREATURES = [(f"sfx_count{n}", WORDS[n - 1] + ".", "am_onyx", 0.8, "en-us", "counter") for n in range(1, 11)] + [
    ("sfx_mimic_voice1", "Over here!", "af_nicole", 1.0, "en-us", "mimic"),
    ("sfx_mimic_voice2", "Hello? Is someone there?", "am_echo", 1.0, "en-us", "mimic"),
    ("sfx_mimic_voice3", "Help me. Please.", "af_sky", 0.95, "en-us", "mimic"),
]

TRIM = ("silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
        "silenceremove=start_periods=1:start_threshold=-45dB,areverse")
FX = {
    "host": "",
    # Lower, breathy and echoing.
    "counter": "asetrate=24000*0.82,aresample=24000,highpass=f=120,aecho=0.8:0.6:60|140:0.35|0.2,",
    "mimic": "",
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


lines = json.load(open(os.path.join(HERE, "host_lines.json")))
made = 0
for host, (voice, speed, lang) in HOSTS.items():
    for line in lines:
        made += record(f"v_{host}_{line['id']}", line[host], voice, speed, lang, "host")
sounds = os.path.join(ROOT, "App", "Sounds")
os.makedirs(sounds, exist_ok=True)
for name, text, voice, speed, lang, fx in CREATURES:
    made += record(name, text, voice, speed, lang, fx, sounds)
if os.path.exists(raw):
    os.remove(raw)
print(f"{made} new recordings ({len(lines)} lines per Host)")
