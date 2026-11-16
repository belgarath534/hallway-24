"""Records the Hosts whose voice is "chatterbox:<reference>" with Chatterbox Multilingual (Resemble AI, MIT license).
Chatterbox copies the voice of a short reference recording (App/Voices/<reference>.m4a) and speaks any language.
It's slow without an NVIDIA graphics card: about 50 seconds a line, so a whole Host takes about two hours.

Setup (once):
    python3 -m venv tools/.cbvenv
    tools/.cbvenv/bin/pip install torch torchaudio --index-url https://download.pytorch.org/whl/cpu
    tools/.cbvenv/bin/pip install chatterbox-tts
Run:
    tools/.cbvenv/bin/python tools/make_voices_chatterbox.py           # only lines without a recording
    tools/.cbvenv/bin/python tools/make_voices_chatterbox.py --all     # redo everything
Needs ffmpeg. The model downloads itself the first time.
"""
import json, os, subprocess, sys
import torchaudio as ta
from chatterbox.mtl_tts import ChatterboxMultilingualTTS

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "App", "Voices")
ALL = "--all" in sys.argv
TRIM = ("silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
        "silenceremove=start_periods=1:start_threshold=-45dB,areverse")

hosts = [h for h in json.load(open(os.path.join(HERE, "host_lines.json"))) if h["voice"].startswith("chatterbox:")]
model = ChatterboxMultilingualTTS.from_pretrained(device="cpu")
raw = os.path.join(HERE, "_cb_raw.wav")
made = 0
for h in hosts:
    reference = os.path.join(OUT, h["voice"].split(":", 1)[1] + ".m4a")
    language = h["lang"].split("-")[0]
    for line_id, text in sorted(h["lines"].items()):
        target = os.path.join(OUT, f"v_{h['host']}_{line_id}.m4a")
        if os.path.exists(target) and not ALL:
            continue
        wav = model.generate(text, language_id=language, audio_prompt_path=reference)
        ta.save(raw, wav, model.sr)
        part = target + ".part.m4a"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", raw, "-af", TRIM + ",loudnorm=I=-16:TP=-1.5,aresample=44100",
                        "-ac", "1", "-c:a", "aac", "-b:a", "64k", part], check=True)
        os.replace(part, target)   # only finished recordings get the real name
        made += 1
        print(h["host"], line_id, flush=True)
if os.path.exists(raw):
    os.remove(raw)
print(f"{made} new recordings")
