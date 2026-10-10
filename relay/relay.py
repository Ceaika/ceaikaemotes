"""Small emote relay. It stores emote events, not game commands or files."""

import argparse
import hmac
import ipaddress
import json
import re
import secrets
import threading
import time
from collections import OrderedDict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

VERSION = "0.2.0"
MAX_BODY_BYTES = 2048
MAX_ROOM_PLAYERS = 32
PEER_TIMEOUT_SECONDS = 6
REQUEST_TIMEOUT_SECONDS = 3
MAX_CONNECTIONS = 16

EMOTES = (
    "bbd_traversal",
    "emote_dancemoves",
    "emote_electroshuffle",
    "electroswing_auto",
    "emote_floss",
    "emote_freestylin",
    "griddy_traversal",
    "emote_hype",
    "emote_oj",
    "emote_laugh",
    "emote_rambunctious",
    "emote_technozombie",
    "emote_smoothmoves",
    "emote_squatkick",
    "emote_takethel",
    "emote_worm",
)
TRAVERSAL = ("bbd_traversal", "griddy_traversal")


class Room:
    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self.peers = {}
        self.lock = threading.Lock()

    def sync(self, data):
        if not isinstance(data, dict):
            raise ValueError("object required")
        if set(data) - {"uid", "map", "nonce", "emote", "traversal"}:
            raise ValueError("unknown fields")

        player_id = data.get("uid", "")
        map_name = data.get("map", "")
        playback_id = data.get("nonce", "")
        emote = data.get("emote", "")
        traversal = data.get("traversal", False)

        if (
            not isinstance(player_id, str)
            or not re.fullmatch(r"[0-9]{1,24}", player_id)
            or int(player_id) == 0
        ):
            raise ValueError("invalid UID")
        if not isinstance(map_name, str) or not re.fullmatch(r"mp_[a-zA-Z0-9_]{1,80}", map_name):
            raise ValueError("invalid map")
        if not isinstance(playback_id, str) or not re.fullmatch(
            r"[a-zA-Z0-9_.-]{1,80}", playback_id
        ):
            raise ValueError("invalid nonce")
        if not isinstance(emote, str) or (emote != "" and emote not in EMOTES):
            raise ValueError("unknown emote")
        if not isinstance(traversal, bool):
            raise ValueError("invalid traversal")
        if traversal and emote not in TRAVERSAL:
            raise ValueError("emote is stationary")

        now = self.clock()
        with self.lock:
            self.peers = {
                uid: peer
                for uid, peer in self.peers.items()
                if now - peer["seen"] < PEER_TIMEOUT_SECONDS
            }
            previous = self.peers.get(player_id)
            if previous and now - previous["seen"] < 0.15:
                return 429, {"error": "slow down"}
            if not previous and len(self.peers) >= MAX_ROOM_PLAYERS:
                return 503, {"error": "room full"}

            # same dance, same start time. dont restart it on every poll.
            same_playback = previous and (
                previous["nonce"],
                previous["emote"],
                previous["map"],
                previous["traversal"],
            ) == (playback_id, emote, map_name, traversal)
            started_at = previous["start"] if same_playback else now
            self.peers[player_id] = {
                "uid": player_id,
                "map": map_name,
                "nonce": playback_id,
                "emote": emote,
                "traversal": traversal,
                "start": started_at,
                "seen": now,
            }
            peers = [
                {
                    "uid": peer["uid"],
                    "nonce": peer["nonce"],
                    "emote": peer["emote"],
                    "traversal": peer["traversal"],
                    "age": round(now - peer["start"], 3),
                }
                for peer in self.peers.values()
                if peer["map"] == map_name
            ]
            return 200, {"peers": peers}


class RequestBudget:
    """Bound total traffic as well as traffic from one address."""

    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self.global_tokens = 160.0
        self.last_global = clock()
        self.addresses = OrderedDict()
        self.lock = threading.Lock()

    def allow(self, address, shared_proxy=False):
        now = self.clock()
        with self.lock:
            self.global_tokens = min(160.0, self.global_tokens + (now - self.last_global) * 80)
            self.last_global = now
            if self.global_tokens < 1:
                return False
            self.global_tokens -= 1

            # without a configured proxy header all proxied users share this bucket.
            rate, capacity = (80.0, 160.0) if shared_proxy else (12.0, 24.0)
            tokens, last = self.addresses.pop(address, (capacity, now))
            tokens = min(capacity, tokens + (now - last) * rate)
            allowed = tokens >= 1
            self.addresses[address] = (tokens - 1 if allowed else tokens, now)
            while len(self.addresses) > 1024:
                self.addresses.popitem(last=False)
            return allowed


class Server(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 16

    def __init__(self, address, key, trust_proxy_header=False):
        super().__init__(address, Handler)
        self.key = key
        self.room = Room()
        self.budget = RequestBudget()
        self.trust_proxy_header = trust_proxy_header
        self.slots = threading.BoundedSemaphore(MAX_CONNECTIONS)

    def process_request(self, request, address):
        if not self.slots.acquire(False):
            request.close()
            return
        try:
            super().process_request(request, address)
        except Exception:
            self.slots.release()
            raise

    def process_request_thread(self, request, address):
        try:
            super().process_request_thread(request, address)
        finally:
            self.slots.release()

    def handle_error(self, request, client_address):
        # dont dump request details or credentials into logs.
        pass


def reject_nonfinite_number(value):
    raise ValueError("non-finite JSON number")


class Handler(BaseHTTPRequestHandler):
    server_version = "EmoteRelay"
    sys_version = ""

    def setup(self):
        super().setup()
        self.connection.settimeout(REQUEST_TIMEOUT_SECONDS)

    def log_message(self, *args):
        # no keys, player IDs or request bodies in access logs.
        pass

    def reply(self, status, body):
        raw = json.dumps(body, separators=(",", ":")).encode()
        self.close_connection = True
        try:
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Connection", "close")
            self.send_header("Content-Length", str(len(raw)))
            if status == 429:
                self.send_header("Retry-After", "1")
            self.end_headers()
            self.wfile.write(raw)
        except (OSError, TimeoutError):
            pass

    def send_error(self, code, message=None, explain=None):
        self.reply(code, {"error": "request rejected"})

    def request_allowed(self):
        address = self.client_address[0]
        shared_proxy = ipaddress.ip_address(address).is_loopback
        if self.server.trust_proxy_header:
            supplied = self.headers.get_all("X-Emote-Client-IP", [])
            if len(supplied) != 1:
                self.reply(400, {"error": "proxy header required"})
                return False
            try:
                address = str(ipaddress.ip_address(supplied[0]))
            except ValueError:
                self.reply(400, {"error": "invalid proxy header"})
                return False
            shared_proxy = False
        if not self.server.budget.allow(address, shared_proxy):
            self.reply(429, {"error": "slow down"})
            return False
        return True

    def do_GET(self):
        if not self.request_allowed():
            return
        if self.path != "/health":
            self.reply(404, {"error": "not found"})
            return
        self.reply(
            200, {"service": "emote-relay-prototype", "version": VERSION, "emotes": len(EMOTES)}
        )

    def do_POST(self):
        if not self.request_allowed():
            return
        if self.path != "/sync":
            self.reply(404, {"error": "not found"})
            return
        auth = self.headers.get_all("Authorization", [])
        if (
            len(auth) != 1
            or len(auth[0]) > 256
            or not hmac.compare_digest(auth[0].encode(), ("Bearer " + self.server.key).encode())
        ):
            self.reply(401, {"error": "invalid room key"})
            return
        lengths = self.headers.get_all("Content-Length", [])
        if self.headers.get("Transfer-Encoding") is not None or len(lengths) != 1:
            self.reply(400, {"error": "invalid framing"})
            return
        try:
            if not lengths[0].isascii() or not lengths[0].isdigit():
                raise ValueError("invalid length")
            length = int(lengths[0])
            if not 1 <= length <= MAX_BODY_BYTES:
                self.reply(413, {"error": "invalid size"})
                return
            raw = self.rfile.read(length)
            if len(raw) != length:
                raise ValueError("incomplete body")
            data = json.loads(raw, parse_constant=reject_nonfinite_number)
            status, body = self.server.room.sync(data)
        except (ValueError, TypeError, UnicodeError, RecursionError):
            self.reply(400, {"error": "invalid request"})
            return
        except (OSError, TimeoutError):
            self.reply(408, {"error": "request timeout"})
            return
        self.reply(status, body)

    def unsupported_method(self):
        self.reply(405, {"error": "method not allowed"})

    do_PUT = do_DELETE = do_PATCH = do_OPTIONS = do_HEAD = do_CONNECT = do_TRACE = (
        unsupported_method
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument("--key-file", default="room.key")
    parser.add_argument("--trust-proxy-header", action="store_true")
    args = parser.parse_args()
    key_path = Path(args.key_file)
    if not key_path.exists():
        # create it privately from the start, not after writing it.
        import os

        descriptor = os.open(key_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as output:
            output.write(secrets.token_hex(24) + "\n")
    key = key_path.read_text().strip()
    if not re.fullmatch(r"[a-zA-Z0-9_-]{24,128}", key):
        raise SystemExit("Invalid room key file")
    server = Server((args.bind, args.port), key, args.trust_proxy_header)
    print(f"Emote relay {VERSION} listening on {args.bind}:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
