"""App Store Connect API helpers shared by the store scripts."""
import os
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


