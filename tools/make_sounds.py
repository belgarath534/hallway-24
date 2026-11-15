"""Builds the game's sounds, ambiences and music from the downloaded free packs (see CREDITS.md).

    python3 tools/make_sounds.py <downloads folder>

The downloads folder holds the packs as unzipped (any layout: files are found by name) and the music mp3s.
Everything is converted for the app: effects and ambiences mono 44.1 kHz AAC, music stereo AAC.
Needs ffmpeg. The Counter's and the Mimic's voices come from make_voices.py instead.
"""
import os, subprocess, sys

SRC = sys.argv[1]
ALL = "--all" in sys.argv   # redo files that already exist
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOUNDS = os.path.join(ROOT, "App", "Sounds")
MUSIC = os.path.join(ROOT, "App", "Music")

index = {}
for folder, _, files in os.walk(SRC):
    if "__MACOSX" in folder:
        continue
    for f in files:
        index.setdefault(f, os.path.join(folder, f))


def find(name):
    if name not in index:
        sys.exit(f"Can't find {name} in {SRC}")
    return index[name]


def ffmpeg(inputs, graph, out, mono=True, bitrate="64k"):
    if os.path.exists(out) and not ALL:
        return
    cmd = ["ffmpeg", "-v", "error", "-y"]
    for i in inputs:
        cmd += ["-i", find(i)]
    cmd += ["-filter_complex", graph, "-map", "[o]", "-ar", "44100", "-ac", "1" if mono else "2", "-c:a", "aac", "-b:a", bitrate, out]
    subprocess.run(cmd, check=True)


NORM = "loudnorm=I=-18:TP=-1.5"


def sfx(name, src, trim=None, extra="", gain=0.0):
    """One sound from one file: optional trim (seconds), fades, even loudness."""
    t = f"atrim=0:{trim},afade=t=out:st={max(trim - 0.25, 0)}:d=0.25," if trim else ""
    ffmpeg([src], f"[0:a]aformat=channel_layouts=mono,{t}{extra}{NORM},volume={gain}dB[o]", os.path.join(SOUNDS, f"sfx_{name}.m4a"))


def repeat(name, src, times, gap, trim=None, fade_steps=False, gain=0.0):
    """The same sound several times in a row (ticking, running steps)."""
    parts, labels = [], []
    for k in range(times):
        vol = 1.0 - (0.5 * k / max(times - 1, 1) if fade_steps else 0)
        cut = f"atrim=0:{trim}," if trim else ""
        parts.append(f"[0:a]aformat=channel_layouts=mono,{cut}adelay={int(k * gap * 1000)},volume={vol:.2f}[p{k}]")
        labels.append(f"[p{k}]")
    graph = ";".join(parts) + f";{''.join(labels)}amix=inputs={times}:normalize=0,{NORM},volume={gain}dB[o]"
    ffmpeg([src], graph, os.path.join(SOUNDS, f"sfx_{name}.m4a"))


def mix(name, a, b, delay_b=0.0, trim=None):
    """Two sounds layered (b starts a little later)."""
    t = f",atrim=0:{trim},afade=t=out:st={trim - 0.3}:d=0.3" if trim else ""
    graph = (f"[0:a]aformat=channel_layouts=mono[a];[1:a]aformat=channel_layouts=mono,adelay={int(delay_b * 1000)}[b];"
             f"[a][b]amix=inputs=2:normalize=0{t},{NORM}[o]")
    ffmpeg([a, b], graph, os.path.join(SOUNDS, f"sfx_{name}.m4a"))


def loop(name, src, length, start=0.0):
    """An ambience that loops without a click: the end is crossfaded into the start."""
    x = 2.0
    duration = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", find(src)],
                                    capture_output=True, text=True, check=True).stdout)
    length = min(length, duration - start - x - 0.1)
    graph = (f"[0:a]aformat=channel_layouts=mono,asplit[a][b];"
             f"[a]atrim={start}:{start + length},asetpts=PTS-STARTPTS[main];"
             f"[b]atrim={start + length}:{start + length + x},asetpts=PTS-STARTPTS[tail];"
             f"[main][tail]acrossfade=d={x}:c1=tri:c2=tri,{NORM}[o]")
    try:
        ffmpeg([src], graph, os.path.join(SOUNDS, f"{name}.m4a"))
    except subprocess.CalledProcessError:   # Too short to crossfade: plain fades.
        ffmpeg([src], f"[0:a]aformat=channel_layouts=mono,afade=t=in:d=0.5,{NORM}[o]", os.path.join(SOUNDS, f"{name}.m4a"))


def music(name, src):
    ffmpeg([src], "[0:a]loudnorm=I=-20:TP=-1.5[o]", os.path.join(MUSIC, f"{name}.m4a"), mono=False, bitrate="96k")


os.makedirs(SOUNDS, exist_ok=True)
os.makedirs(MUSIC, exist_ok=True)

# Through the doors. Good rooms:
sfx("hint_bedroom", "bell_01.ogg", trim=2.5)
# Short sounds are repeated so every hint lasts long enough to recognise.
repeat("hint_kitchen", "dishes_01.ogg", 2, 0.75)
repeat("hint_vault", "keys_01.ogg", 3, 0.45)
repeat("hint_storage", "wooded_box_open.ogg", 2, 0.8)
sfx("hint_empty", "sfx100v2_air_01.ogg", trim=2.5)
# …and creatures:
sfx("hint_drip", "Blood_Dripping_Loop_00.mp3", trim=2.5, gain=10)
repeat("hint_static", "noise_01.ogg", 3, 0.38)
mix("hint_crawler", "wood_squeak_01.ogg", "stomp_01.ogg", 0.5, trim=2.5)
repeat("hint_counter", "switch_02.ogg", 4, 0.55, trim=0.3)

# Doors and you
sfx("door_open", "door_open.ogg", trim=2.0)
sfx("door_close", "door_close_01.ogg", trim=1.5)
sfx("locker", "metal_close_01.ogg", trim=1.5)
repeat("run_away", "sfx100v2_footstep_01.ogg", 6, 0.22, trim=0.25, fade_steps=True)

# Rooms
sfx("heal", "bell_02.ogg", trim=2.5)
sfx("coins", "keys_02.ogg", trim=2.0)
sfx("item_get", "bell_03.ogg", trim=2.0)
sfx("nothing", "wood_squeak_02.ogg", trim=2.0)

# The Drip
sfx("drip1", "Blood_Drip_00.mp3", trim=1.0, gain=6)
sfx("drip2", "Blood_Drip_03.mp3", trim=1.0, gain=6)
sfx("drip3", "Blood_Drip_06.mp3", trim=1.0, gain=6)
sfx("splash", "splash_05.ogg", trim=2.0, gain=9)
# Static
sfx("buzz", "noise_02.ogg", trim=0.9)
sfx("zap_out", "weird_02.ogg", trim=1.5)
# The Crawler
sfx("crawl1", "sfx100v2_footstep_wet_01.ogg", trim=0.6)
sfx("crawl2", "sfx100v2_footstep_wet_02.ogg", trim=0.6)
sfx("crawl3", "sfx100v2_footstep_wet_03.ogg", trim=0.6)
sfx("growl", "monster_03.ogg", trim=2.0, gain=2)
sfx("sniff", "nose.ogg", trim=2.0)
# The Counter (its numbers come from make_voices.py)
sfx("counter_sigh", "breath.ogg", trim=2.5)
sfx("decoy_knock", "wood_hit_01.ogg", trim=1.0)
sfx("decoy_creak", "wood_cracking_01.ogg", trim=1.5)

# Results
mix("hit", "attack_01.ogg", "Bonecrack_00.mp3", 0.05, trim=1.5)  # made louder below
sfx("charm_break", "glass_02.ogg", trim=1.5)
sfx("survive", "Jingle_Achievement_00.mp3")
sfx("heartbeat", "heartbeat_slow_0.wav")
sfx("win_sting", "Jingle_Win_00.mp3")
sfx("lose_sting", "Jingle_Lose_00.mp3")

# Ambiences
loop("amb_hallway", "abandonedbuildingambience.wav", 45)
loop("amb_deep", "Ambience_MonstersBelly_00.mp3", 30)
loop("amb_room", "sfx100v2_loop_ambient_01.ogg", 20)
loop("amb_shop", "sfx100v2_loop_ambient_04.ogg", 20)

# Music by Kevin MacLeod (incompetech.com), CC BY 4.0
music("mus_menu", "Comfortable Mystery 4.mp3")
music("mus_early", "Lightless Dawn.mp3")
music("mus_middle", "Penumbra.mp3")
music("mus_late", "Ossuary 6 - Air.mp3")
music("mus_calm", "Clean Soul.mp3")
music("mus_win", "Lasting Hope.mp3")
music("mus_lose", "Darkness Speaks.mp3")
print("Done.")
