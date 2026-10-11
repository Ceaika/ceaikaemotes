"""Verify EA credentials, then issue short-lived emote-only sessions.

The Stryder exchange follows R2Northstar/Atlas pkg/stryder/stryder.go.
Never log the upstream URL, response, auth code or session bearer.
"""

import hashlib
import json
import re
import secrets
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

SESSION_SECONDS = 1800
MAX_SESSIONS = 2048


class AuthRejected(Exception):
    pass


class AuthorityUnavailable(Exception):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def valid_uid(uid):
    return (
        isinstance(uid, str)
        and re.fullmatch(r"[1-9][0-9]{0,19}", uid)
        and int(uid) <= 2**64 - 1
    )


def verify_response(raw):
    try:
        try:
            data = json.loads(raw)
        except (ValueError, UnicodeError):
            # Stryder sometimes quotes an already-serialized nested error object.
            data = json.loads(raw.replace(b'"{', b"{").replace(b'}"', b"}"))
    except (ValueError, UnicodeError, RecursionError):
        raise AuthorityUnavailable() from None
    if not isinstance(data, dict):
        raise AuthorityUnavailable()
    if data.get("success") is False:
        raise AuthRejected()
    if "/titanfall-2" not in str(data.get("storeUri", "")):
        raise AuthRejected()
    access = data.get("hasOnlineAccess")
    if type(access) not in (int, str) or str(access) != "1":
        raise AuthRejected()


def verify_origin(uid, code):
    query = urllib.parse.urlencode(
        {
            "qt": "origin-requesttoken",
            "type": "server_token",
            "code": code,
            "userId": format(int(uid), "X"),
            "forceTrial": "0",
            "proto": "0",
            "json": "1",
            "env": "production",
        }
    )
    request = urllib.request.Request(
        "https://r2-pc.stryder.respawn.com/nucleus-oauth.php?" + query,
        headers={"Accept": "application/json"},
    )
    try:
        with urllib.request.build_opener(NoRedirect()).open(
            request, timeout=5
        ) as response:
            raw = response.read(65537)
            if response.status != 200 or len(raw) > 65536:
                raise AuthorityUnavailable()
    except (OSError, urllib.error.URLError, ValueError):
        # Upstream exception strings can contain the credential-bearing URL.
        raise AuthorityUnavailable() from None
    verify_response(raw)


class Sessions:
    def __init__(self, verifier=verify_origin, clock=time.monotonic):
        self.verifier = verifier
        self.clock = clock
        self.sessions = {}
        self.used_codes = {}
        self.lock = threading.Lock()
        self.verification_slots = threading.BoundedSemaphore(2)

    def prune(self, now):
        self.sessions = {k: v for k, v in self.sessions.items() if v[1] > now}
        self.used_codes = {k: v for k, v in self.used_codes.items() if v > now}

    def authenticate(self, data):
        if not isinstance(data, dict) or set(data) != {"uid", "code"}:
            raise ValueError("invalid auth request")
        uid, code = data["uid"], data["code"]
        if (
            not valid_uid(uid)
            or not isinstance(code, str)
            or not 8 <= len(code) <= 4096
        ):
            raise ValueError("invalid auth request")
        if not code.isascii() or any(ord(c) <= 32 or ord(c) == 127 for c in code):
            raise ValueError("invalid auth request")
        digest = hashlib.sha256(code.encode()).digest()
        now = self.clock()
        with self.lock:
            self.prune(now)
            if digest in self.used_codes:
                raise AuthRejected()
            if len(self.sessions) >= MAX_SESSIONS or len(self.used_codes) >= 8192:
                raise AuthorityUnavailable()
            self.used_codes[digest] = now + SESSION_SECONDS
        if not self.verification_slots.acquire(False):
            raise AuthorityUnavailable()
        try:
            self.verifier(uid, code)
        finally:
            self.verification_slots.release()
        token = secrets.token_hex(32)
        with self.lock:
            self.prune(self.clock())
            # One active credential per account. Reauth invalidates the old session.
            self.sessions = {k: v for k, v in self.sessions.items() if v[0] != uid}
            self.sessions[hashlib.sha256(token.encode()).digest()] = (
                uid,
                self.clock() + SESSION_SECONDS,
            )
        return {"token": token, "expires_in": SESSION_SECONDS}

    def resolve(self, token):
        if not isinstance(token, str) or not re.fullmatch(r"[a-f0-9]{64}", token):
            return None
        with self.lock:
            self.prune(self.clock())
            row = self.sessions.get(hashlib.sha256(token.encode()).digest())
            return row[0] if row else None
