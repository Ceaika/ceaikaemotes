import http.client, json, threading, unittest
from identity import (
    Sessions,
    AuthRejected,
    AuthorityUnavailable,
    verify_response,
    valid_uid,
)
from relay import Server


class IdentityTests(unittest.TestCase):
    def test_entitlement_and_online_access_required(self):
        good = {"storeUri": "origin://store/titanfall-2", "hasOnlineAccess": 1}
        verify_response(json.dumps(good).encode())
        for bad in [
            dict(good, success=False),
            dict(good, hasOnlineAccess=0),
            dict(good, hasOnlineAccess=True),
            dict(good, storeUri="other"),
            {},
        ]:
            with self.assertRaises(AuthRejected):
                verify_response(json.dumps(bad).encode())
        with self.assertRaises(AuthorityUnavailable):
            verify_response(b"not json")

    def test_uid_format(self):
        for uid in ["0", "0123", "-1", "1e3", str(2**64), 123, None]:
            self.assertFalse(valid_uid(uid))
        self.assertTrue(valid_uid("1000000000001"))

    def test_expiry_reauth_and_code_replay(self):
        now = [0.0]
        s = Sessions(verifier=lambda u, c: None, clock=lambda: now[0])
        first = s.authenticate({"uid": "123", "code": "test-code-one"})["token"]
        self.assertEqual(s.resolve(first), "123")
        with self.assertRaises(AuthRejected):
            s.authenticate({"uid": "456", "code": "test-code-one"})
        second = s.authenticate({"uid": "123", "code": "test-code-two"})["token"]
        self.assertIsNone(s.resolve(first))
        self.assertEqual(s.resolve(second), "123")
        now[0] = 1801
        self.assertIsNone(s.resolve(second))
        self.assertIsNone(s.resolve("public-room-key"))

    def test_failed_authority_never_creates_session(self):
        def unavailable(u, c):
            raise AuthorityUnavailable()

        s = Sessions(verifier=unavailable)
        with self.assertRaises(AuthorityUnavailable):
            s.authenticate({"uid": "123", "code": "test-code-one"})
        self.assertEqual(s.sessions, {})

    def test_http_cannot_impersonate_another_uid(self):
        def verify(uid, code):
            if (uid, code) != ("123", "test-code-alice"):
                raise AuthRejected()

        srv = Server(("127.0.0.1", 0), "public-room-key")
        srv.sessions = Sessions(verifier=verify)
        thread = threading.Thread(target=srv.serve_forever, daemon=True)
        thread.start()

        def post(path, key, data):
            c = http.client.HTTPConnection("127.0.0.1", srv.server_port)
            c.request(
                "POST", path, json.dumps(data), {"Authorization": "Bearer " + key}
            )
            r = c.getresponse()
            out = (r.status, json.loads(r.read()))
            c.close()
            return out

        try:
            event = {"map": "mp_colony", "nonce": "one", "emote": "emote_oj"}
            self.assertEqual(
                post("/sync", "public-room-key", dict(event, uid="456"))[0], 401
            )
            self.assertEqual(
                post(
                    "/auth",
                    "public-room-key",
                    {"uid": "456", "code": "test-code-wrong"},
                )[0],
                401,
            )
            status, body = post(
                "/auth", "public-room-key", {"uid": "123", "code": "test-code-alice"}
            )
            self.assertEqual(status, 200)
            token = body["token"]
            self.assertEqual(post("/sync", token, dict(event, uid="456"))[0], 400)
            status, body = post("/sync", token, event)
            self.assertEqual(status, 200)
            self.assertEqual(body["peers"][0]["uid"], "123")
            self.assertEqual(
                post(
                    "/auth",
                    "public-room-key",
                    {"uid": "123", "code": "test-code-alice"},
                )[0],
                401,
            )
        finally:
            srv.shutdown()
            srv.server_close()
            thread.join()


if __name__ == "__main__":
    unittest.main()
