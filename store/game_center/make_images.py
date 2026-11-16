"""Draws the 512x512 Game Center achievement pictures from achievements.json: a glowing door and the title."""
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).parent
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"
GOLD = (245, 195, 110)


def wrap(text, font, width, d):
    words, lines, line = text.split(), [], ""
    for w in words:
        test = (line + " " + w).strip()
        if d.textlength(test, font=font) <= width:
            line = test
        else:
            lines.append(line)
            line = w
    return lines + [line]


(HERE / "images").mkdir(exist_ok=True)
for a in json.loads((HERE / "achievements.json").read_text()):
    S = 512
    img = Image.new("RGB", (S, S), (10, 5, 6))
    d = ImageDraw.Draw(img)
    for r in range(S // 2, 0, -2):  # dark red glow in the middle
        t = r / (S / 2)
        d.ellipse([S / 2 - r, S / 2 - r, S / 2 + r, S / 2 + r], fill=(int(60 * (1 - t) + 10), int(14 * (1 - t) + 5), int(16 * (1 - t) + 6)))
    glow = Image.new("L", (S, S), 0)
    g = ImageDraw.Draw(glow)
    door = [196, 70, 316, 250]
    g.rectangle(door, outline=255, width=12)
    g.line([(door[0], door[3]), (door[2], door[3])], fill=255, width=22)
    img.paste(GOLD, mask=glow.filter(ImageFilter.GaussianBlur(14)))
    d = ImageDraw.Draw(img)
    d.rectangle(door, fill=(45, 20, 14), outline=GOLD, width=6)
    d.ellipse([290, 158, 304, 172], fill=GOLD)
    d.ellipse([16, 16, S - 16, S - 16], outline=GOLD, width=8)
    font = ImageFont.truetype(FONT, 44)
    lines = wrap(a["title"], font, 380, d)
    y = 300 if len(lines) == 1 else 280
    for line in lines:
        w = d.textlength(line, font=font)
        d.text(((S - w) / 2, y), line, font=font, fill=(245, 230, 210))
        y += 54
    img.save(HERE / "images" / f"{a['id']}.png")
print("Drew", len(list((HERE / "images").glob("*.png"))), "pictures")
