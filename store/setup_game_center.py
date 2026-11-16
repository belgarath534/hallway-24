"""Creates the game's Game Center achievements and leaderboards in App Store Connect (idempotent).
Run by the "App Store" GitHub workflow. Adapted from the truck sim's. English and Portuguese text.

  - Turns on Game Center for the app
  - Creates each achievement in game_center/achievements.json with its English text and picture
  - Creates the leaderboards (furthest hour, nights survived, creatures survived)
  - Creates a challenge (iOS 26 Games app): "How far can you get?" on the furthest-hour leaderboard.
    Friends challenge each other for a day, three days or a week. It goes to App Review with the next
    version of the app; this script never submits anything.
Things that already exist are left alone, except missing text or pictures, which are added.
"""
import hashlib
import os
import sys
import time

import jwt
import requests

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE = "com.hallway24.Hallway24"


def private_key():
    key = os.environ["APP_STORE_CONNECT_PRIVATE_KEY"].strip()
    if key.startswith("@file:"):
        key = open(os.path.expanduser(key[6:])).read()
    elif key.startswith("@env:"):
        key = os.environ[key[5:]]
    key = key.replace("\\n", "\n").strip().strip('"')
    if "BEGIN" not in key:
        body = "".join(key.split())
        key = "-----BEGIN PRIVATE KEY-----\n" + "\n".join(body[i:i + 64] for i in range(0, len(body), 64)) + "\n-----END PRIVATE KEY-----"
    return key


def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"], "iat": now, "exp": now + 1000,
                       "aud": "appstoreconnect-v1"}, private_key(), algorithm="ES256",
                      headers={"kid": os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"], "typ": "JWT"})

S = requests.Session()
S.headers["Authorization"] = "Bearer " + token()

import json
from pathlib import Path

HERE = Path(__file__).parent / "game_center"
problems = []


class ApiError(Exception):
    pass


def call(method, path, ok404=False, **kw):
    r = S.request(method, path if path.startswith("http") else API + path, timeout=120, **kw)
    if ok404 and r.status_code == 404:
        return None
    if r.status_code >= 400:
        raise ApiError(f"{method} {path} -> {r.status_code}: {r.text[:1200]}")
    return r.json() if r.content else {}


def rel(kind, rid):
    return {"data": {"type": kind, "id": rid}}


def all_pages(path, **params):
    out, url = [], path
    while url:
        page = call("GET", url, params=params if url == path else None)
        out += page["data"]
        url = page.get("links", {}).get("next")
    return out


def upload(kind, owner_rel, owner_kind, owner_id, file_path):
    data = file_path.read_bytes()
    item = call("POST", f"/{kind}", json={"data": {"type": kind,
                "attributes": {"fileName": file_path.name, "fileSize": len(data)},
                "relationships": {owner_rel: rel(owner_kind, owner_id)}}})["data"]
    for op in item["attributes"]["uploadOperations"]:
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        r = requests.request(op["method"], op["url"], headers=headers, data=chunk, timeout=120)
        if r.status_code >= 400:
            raise ApiError(f"Upload of {file_path.name} failed: {r.status_code} {r.text[:300]}")
    call("PATCH", f"/{kind}/{item['id']}", json={"data": {"type": kind, "id": item["id"], "attributes": {"uploaded": True}}})


app = call("GET", "/apps", params={"filter[bundleId]": BUNDLE})["data"][0]["id"]

# ------------------------------------------------------------------ Game Center for the app
detail = call("GET", f"/apps/{app}/gameCenterDetail", ok404=True)
if detail and detail.get("data"):
    detail_id = detail["data"]["id"]
    print("Game Center is already on for the app.")
else:
    detail_id = call("POST", "/gameCenterDetails", json={"data": {"type": "gameCenterDetails",
                     "relationships": {"app": rel("apps", app)}}})["data"]["id"]
    print("Turned on Game Center for the app.")

# ------------------------------------------------------------------ achievements
existing = {a["attributes"]["vendorIdentifier"]: a
            for a in all_pages(f"/gameCenterDetails/{detail_id}/gameCenterAchievements", limit=200)}
for a in json.loads((HERE / "achievements.json").read_text()):
    vendor = "hallway24." + a["id"]
    try:
        if vendor in existing:
            ach_id = existing[vendor]["id"]
        else:
            ach_id = call("POST", "/gameCenterAchievements", json={"data": {"type": "gameCenterAchievements",
                          "attributes": {"referenceName": a["title"], "vendorIdentifier": vendor, "points": a["points"],
                                         "showBeforeEarned": True, "repeatable": False},
                          "relationships": {"gameCenterDetail": rel("gameCenterDetails", detail_id)}}})["data"]["id"]
            print("Created achievement", a["title"])
        locs = call("GET", f"/gameCenterAchievements/{ach_id}/localizations")["data"]
        for locale, title, detail in (("en-US", a["title"], a["detail"]), ("pt-BR", a["title_pt"], a["detail_pt"])):
            loc = next((l for l in locs if l["attributes"]["locale"] == locale), None)
            if not loc:
                loc = call("POST", "/gameCenterAchievementLocalizations", json={"data": {
                    "type": "gameCenterAchievementLocalizations",
                    "attributes": {"locale": locale, "name": title, "beforeEarnedDescription": detail,
                                   "afterEarnedDescription": detail},
                    "relationships": {"gameCenterAchievement": rel("gameCenterAchievements", ach_id)}}})["data"]
            image = call("GET", f"/gameCenterAchievementLocalizations/{loc['id']}/gameCenterAchievementImage", ok404=True)
            if not (image and image.get("data")):
                upload("gameCenterAchievementImages", "gameCenterAchievementLocalization",
                       "gameCenterAchievementLocalizations", loc["id"], HERE / "images" / f"{a['id']}.png")
                print(f"  picture uploaded for {title} ({locale})")
    except Exception as e:  # keep going with the others
        problems.append(f"Achievement {a['title']}: {e}")
        print("FAILED", a["title"], e)

# ------------------------------------------------------------------ leaderboards
LEADERBOARDS = [
    {"vendor": "hallway24.furthest_hour", "name": "Furthest Hour", "name_pt": "Hora Mais Longe", "formatter": "INTEGER",
     "submission": "BEST_SCORE", "suffix": " hours", "singular": " hour", "suffix_pt": " horas", "singular_pt": " hora"},
    {"vendor": "hallway24.nights_survived", "name": "Nights Survived", "name_pt": "Noites Sobrevividas", "formatter": "INTEGER",
     "submission": "MOST_RECENT_SCORE", "suffix": " nights", "singular": " night", "suffix_pt": " noites", "singular_pt": " noite"},
    {"vendor": "hallway24.creatures_survived", "name": "Creatures Survived", "name_pt": "Criaturas Vencidas", "formatter": "INTEGER",
     "submission": "MOST_RECENT_SCORE", "suffix": " creatures", "singular": " creature", "suffix_pt": " criaturas", "singular_pt": " criatura"},
]
boards = {b["attributes"]["vendorIdentifier"]: b
          for b in all_pages(f"/gameCenterDetails/{detail_id}/gameCenterLeaderboards", limit=200)}
for b in LEADERBOARDS:
    try:
        if b["vendor"] in boards:
            board_id = boards[b["vendor"]]["id"]
        else:
            board_id = call("POST", "/gameCenterLeaderboards", json={"data": {"type": "gameCenterLeaderboards",
                            "attributes": {"referenceName": b["name"], "vendorIdentifier": b["vendor"],
                                           "defaultFormatter": b["formatter"], "submissionType": b["submission"],
                                           "scoreSortType": "DESC"},
                            "relationships": {"gameCenterDetail": rel("gameCenterDetails", detail_id)}}})["data"]["id"]
            print("Created leaderboard", b["name"])
        locs = call("GET", f"/gameCenterLeaderboards/{board_id}/localizations")["data"]
        for locale, key in (("en-US", ""), ("pt-BR", "_pt")):
            if any(l["attributes"]["locale"] == locale for l in locs):
                continue
            attrs = {"locale": locale, "name": b["name" + key],
                     "formatterSuffix": b["suffix" + key], "formatterSuffixSingular": b["singular" + key]}
            call("POST", "/gameCenterLeaderboardLocalizations", json={"data": {
                "type": "gameCenterLeaderboardLocalizations", "attributes": attrs,
                "relationships": {"gameCenterLeaderboard": rel("gameCenterLeaderboards", board_id)}}})
            print(f"  {locale} text added for", b["name"])
    except Exception as e:
        problems.append(f"Leaderboard {b['name']}: {e}")
        print("FAILED", b["name"], e)

# ------------------------------------------------------------------ challenges (iOS 26)
# New in 2025: if Apple's API refuses, it's reported as a warning and everything else still counts.
CHALLENGES = [
    {"vendor": "hallway24.challenge.furthest_hour", "reference": "How Far Can You Get",
     "leaderboard": "hallway24.furthest_hour", "image": HERE / "challenge_furthest_hour.png",
     "text": {"en-US": ("How Far Can You Get?", "Who gets furthest down the hallway? Survive as many hours as you can."),
              "pt-BR": ("Até Onde Você Chega?", "Quem vai mais longe no corredor? Sobreviva ao máximo de horas que puder.")}},
]
warnings = []
try:
    boards = {b["attributes"]["vendorIdentifier"]: b
              for b in all_pages(f"/gameCenterDetails/{detail_id}/gameCenterLeaderboards", limit=200)}
    existing_ch = {c["attributes"].get("vendorIdentifier"): c
                   for c in all_pages(f"/gameCenterDetails/{detail_id}/gameCenterChallenges", limit=200)}
    for c in CHALLENGES:
        if c["vendor"] in existing_ch:
            ch_id = existing_ch[c["vendor"]]["id"]
        else:
            ch_id = call("POST", "/gameCenterChallenges", json={"data": {"type": "gameCenterChallenges",
                         "attributes": {"referenceName": c["reference"], "vendorIdentifier": c["vendor"],
                                        "challengeType": "LEADERBOARD", "repeatable": True,
                                        "allowedDurations": ["ONE_DAY", "THREE_DAYS", "ONE_WEEK"]},
                         "relationships": {"gameCenterDetail": rel("gameCenterDetails", detail_id),
                                           "leaderboard": rel("gameCenterLeaderboards", boards[c["leaderboard"]]["id"])}}})["data"]["id"]
            print("Created challenge", c["reference"])
        versions = call("GET", f"/gameCenterChallenges/{ch_id}/versions")["data"]
        if versions:
            ver_id = versions[0]["id"]
        else:
            ver_id = call("POST", "/gameCenterChallengeVersions", json={"data": {"type": "gameCenterChallengeVersions",
                          "relationships": {"challenge": rel("gameCenterChallenges", ch_id)}}})["data"]["id"]
        locs = call("GET", f"/gameCenterChallengeVersions/{ver_id}/localizations")["data"]
        for locale, (name, about) in c["text"].items():
            if not any(l["attributes"]["locale"] == locale for l in locs):
                call("POST", "/gameCenterChallengeLocalizations", json={"data": {"type": "gameCenterChallengeLocalizations",
                     "attributes": {"locale": locale, "name": name, "description": about},
                     "relationships": {"version": rel("gameCenterChallengeVersions", ver_id)}}})
                print(f"  {locale} text added for", c["reference"])
        image = call("GET", f"/gameCenterChallengeVersions/{ver_id}/defaultImage", ok404=True)
        if not (image and image.get("data")):
            upload("gameCenterChallengeImages", "version", "gameCenterChallengeVersions", ver_id, c["image"])
            print("  picture uploaded for", c["reference"])
        # Puts the challenge with the game, so it's reviewed with the next version (not a submission).
        try:
            call("POST", "/gameCenterChallengeVersionReleases", json={"data": {"type": "gameCenterChallengeVersionReleases",
                 "relationships": {"gameCenterDetail": rel("gameCenterDetails", detail_id),
                                   "version": rel("gameCenterChallengeVersions", ver_id)}}})
            print("  ready to go out with the next version:", c["reference"])
        except ApiError as e:
            if "409" not in str(e):
                raise
except Exception as e:
    warnings.append(f"Challenges: {e}")
    print("WARNING (challenges)", e)

print()
for w in warnings:
    print("Warning:", w)
if problems:
    print("Problems:")
    for p in problems:
        print(" -", p)
    sys.exit(1)
print("Game Center is set up: all achievements and leaderboards are in App Store Connect.")
