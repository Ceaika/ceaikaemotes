import http.client
import json
import socket
import threading
import unittest
from relay import RequestBudget, Room, Server


class RelaySecurityTests(unittest.TestCase):
    def setUp(self):
        self.server = Server(("127.0.0.1", 0), "test-secret")
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def request(self, method, path, body=b"{}", headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=5)
        try:
            connection.request(
                method, path, body, headers or {"Authorization": "Bearer test-secret"}
            )
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()

    def test_key_does_not_unlock_files_or_admin_routes(self):
        for path in ("/bridge/poll", "/admin", "/room.key", "/../room.key", "/sync?command=whoami"):
            self.assertEqual(self.request("GET", path)[0], 404)
            self.assertEqual(self.request("POST", path)[0], 404)
        self.assertEqual(self.request("PUT", "/sync")[0], 405)
        self.assertEqual(self.request("CONNECT", "/sync")[0], 405)

    def test_only_known_fields_and_emotes(self):
        event = dict(uid="123", map="mp_colony", nonce="one", emote="emote_oj")
        for invalid in (
            dict(event, command="whoami"),
            dict(event, filename="room.key"),
            dict(event, emote="../room.key"),
            dict(event, traversal="true"),
        ):
            self.assertEqual(self.request("POST", "/sync", json.dumps(invalid).encode())[0], 400)
        self.assertEqual(self.request("POST", "/sync", json.dumps(event).encode())[0], 200)

    def test_bad_json_and_deep_nesting(self):
        for body in (b"null", b"[]", b'{"uid":NaN}', b"{", b"[" * 1000 + b"]" * 1000):
            self.assertEqual(self.request("POST", "/sync", body)[0], 400)

    def test_proxy_header_must_be_explicitly_enabled(self):
        self.assertEqual(
            self.request("GET", "/health", headers={"X-Emote-Client-IP": "not-an-ip"})[0], 200
        )
        self.server.trust_proxy_header = True
        self.assertEqual(self.request("GET", "/health")[0], 400)
        self.assertEqual(
            self.request("GET", "/health", headers={"X-Emote-Client-IP": "not-an-ip"})[0], 400
        )
        self.assertEqual(
            self.request("GET", "/health", headers={"X-Emote-Client-IP": "192.0.2.1"})[0], 200
        )

    def test_ambiguous_http_framing_is_rejected(self):
        for headers in (
            "Content-Length: 2\r\nContent-Length: 2",
            "Content-Length: 2\r\nTransfer-Encoding: chunked",
        ):
            with socket.create_connection(
                ("127.0.0.1", self.server.server_port), timeout=5
            ) as connection:
                request = (
                    "POST /sync HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer test-secret\r\n"
                    + headers
                    + "\r\n\r\n{}"
                )
                connection.sendall(request.encode())
                self.assertIn(b" 400 ", connection.recv(1024).split(b"\r\n")[0])

    def test_token_buckets_and_bounded_memory(self):
        clock = [0.0]
        budget = RequestBudget(lambda: clock[0])
        self.assertTrue(all(budget.allow("192.0.2.1") for _ in range(24)))
        self.assertFalse(budget.allow("192.0.2.1"))
        clock[0] += 1
        self.assertTrue(budget.allow("192.0.2.1"))
        for index in range(1100):
            clock[0] += 1
            budget.allow(str(index))
        self.assertLessEqual(len(budget.addresses), 1024)
        fresh = RequestBudget(lambda: clock[0])
        self.assertTrue(all(fresh.allow(str(i)) for i in range(160)))
        self.assertFalse(fresh.allow("new-client"))

    def test_room_capacity_recovers_after_expiry(self):
        clock = [0.0]
        room = Room(lambda: clock[0])
        for uid in range(1, 33):
            self.assertEqual(
                room.sync(dict(uid=str(uid), map="mp_colony", nonce="one", emote=""))[0], 200
            )
        event = dict(uid="99", map="mp_colony", nonce="one", emote="")
        self.assertEqual(room.sync(event)[0], 503)
        clock[0] = 7
        self.assertEqual(room.sync(event)[0], 200)


if __name__ == "__main__":
    unittest.main()
