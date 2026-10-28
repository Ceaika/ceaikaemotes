import json, threading, time, unittest, urllib.request, urllib.error
from relay import Room, Server, EMOTES, TRAVERSAL, PAIRS, JOINS


class Tests(unittest.TestCase):
    def test_full_catalog_and_traversal_restrictions(self):
        clock = [100.0]
        room = Room(lambda: clock[0])
        for emote in EMOTES:
            clock[0] += 1
            data = dict(
                uid="123", map="mp_colony", nonce=emote, emote=emote, traversal=emote in TRAVERSAL
            )
            code, body = room.sync(data)
            self.assertEqual(code, 200)
            self.assertEqual(body["peers"][0]["emote"], emote)
            self.assertEqual(body["peers"][0]["traversal"], emote in TRAVERSAL)
            if emote not in TRAVERSAL:
                with self.assertRaises(ValueError):
                    room.sync(dict(data, traversal=True))
        # the original 16 stay accepted for older clients
        self.assertGreaterEqual(len(EMOTES), 16)
        self.assertTrue({"emote_laugh", "emote_worm", "griddy_traversal"} <= set(EMOTES))
        self.assertTrue(set(TRAVERSAL) <= set(EMOTES))
        self.assertTrue(set(PAIRS) | set(PAIRS.values()) | set(JOINS) | set(JOINS.values()) <= set(EMOTES))

    def test_paired_partner_shares_the_leaders_timing(self):
        clock = [100.0]
        r = Room(lambda: clock[0])
        r.sync(dict(uid="111", map="mp_colony", nonce="a", emote="emote_lastforever"))
        clock[0] += 3
        code, body = r.sync(dict(uid="222", map="mp_colony", nonce="b", emote="emote_lastforever_b",
                                 sync_uid="111", sync_nonce="a"))
        peers = {p["uid"]: p for p in body["peers"]}
        self.assertEqual(code, 200)
        self.assertEqual(peers["222"]["age"], peers["111"]["age"])
        self.assertEqual(peers["222"]["timeline"], peers["111"]["timeline"] + "-p")
        self.assertFalse(peers["222"]["music"])
        clock[0] += 1
        code, _ = r.sync(dict(uid="333", map="mp_colony", nonce="c", emote="emote_robot",
                              sync_uid="111", sync_nonce="a"))
        self.assertEqual(code, 409)

    def test_locked_facing_is_shared_and_checked(self):
        clock = [100.0]
        r = Room(lambda: clock[0])
        a = dict(uid="111", map="mp_colony", nonce="a", emote="emote_robot")
        self.assertIsNone(r.sync(a)[1]["peers"][0]["yaw"])
        clock[0] += 1
        self.assertEqual(r.sync(dict(a, yaw=91.26))[1]["peers"][0]["yaw"], 91.3)
        clock[0] += 1
        self.assertIsNone(r.sync(a)[1]["peers"][0]["yaw"])  # unlocked again
        for bad in (True, "90", float("nan"), 1e9):
            clock[0] += 1
            with self.assertRaises(ValueError):
                r.sync(dict(a, yaw=bad))

    def test_join_starts_when_joining_and_links_to_the_leader(self):
        clock = [100.0]
        r = Room(lambda: clock[0])
        r.sync(dict(uid="111", map="mp_colony", nonce="a", emote="emote_patpat"))
        clock[0] += 5
        code, body = r.sync(dict(uid="222", map="mp_colony", nonce="b", emote="emote_patpat_b",
                                 sync_uid="111", sync_nonce="a"))
        peers = {p["uid"]: p for p in body["peers"]}
        self.assertEqual(code, 200)
        self.assertEqual(peers["222"]["age"], 0)
        self.assertEqual(peers["222"]["timeline"], peers["111"]["timeline"] + "-j")
        clock[0] += 1
        joined = r.sync(dict(uid="222", map="mp_colony", nonce="b", emote="emote_patpat_b",
                             sync_uid="111", sync_nonce="a"))[1]
        self.assertEqual({p["uid"]: p["age"] for p in joined["peers"]}["222"], 1)

    def test_griddy_traversal_and_legacy_client(self):
        clock = [100.0]
        r = Room(lambda: clock[0])
        a = dict(uid="123", map="mp_colony", nonce="g", emote="griddy_traversal", traversal=True)
        peer = r.sync(a)[1]["peers"][0]
        self.assertTrue(peer["traversal"])
        clock[0] += 1
        self.assertEqual(r.sync(a)[1]["peers"][0]["age"], 1)
        clock[0] += 1
        changed = r.sync(dict(a, traversal=False))[1]["peers"][0]
        self.assertEqual(changed["age"], 0)
        legacy = dict(uid="456", map="mp_colony", nonce="b", emote="bbd_traversal")
        self.assertFalse(r.sync(legacy)[1]["peers"][1]["traversal"])
        with self.assertRaises(ValueError):
            r.sync(dict(a, traversal="true"))

    def test_state_isolation_expiry_and_no_restarts(self):
        clock = [100.0]
        r = Room(lambda: clock[0])
        a = dict(uid="123", map="mp_angel_city", nonce="a", emote="bbd_traversal")
        self.assertEqual(r.sync(a)[0], 200)
        clock[0] += 1
        self.assertEqual(r.sync(a)[1]["peers"][0]["age"], 1)
        b = dict(uid="456", map="mp_colony", nonce="b", emote="")
        self.assertEqual(len(r.sync(b)[1]["peers"]), 1)
        clock[0] += 1
        b["map"] = a["map"]
        self.assertEqual(len(r.sync(b)[1]["peers"]), 2)
        clock[0] += 5
        self.assertEqual(len(r.sync(b)[1]["peers"]), 1)
        with self.assertRaises(ValueError):
            r.sync(dict(a, emote="arbitrary_command"))

    def test_all_emotes_over_http_to_second_peer(self):
        srv = Server(("127.0.0.1", 0), "test-secret")
        thread = threading.Thread(target=srv.serve_forever, daemon=True)
        thread.start()
        try:
            url = f"http://127.0.0.1:{srv.server_port}/sync"

            def post(data):
                req = urllib.request.Request(
                    url, json.dumps(data).encode(), {"Authorization": "Bearer test-secret"}
                )
                return json.load(urllib.request.urlopen(req))

            # one dancer switching emotes: a uid per emote would fill the room
            uid = "100"
            for emote in EMOTES:
                post(
                    dict(
                        uid=uid,
                        map="mp_colony",
                        nonce=emote,
                        emote=emote,
                        traversal=emote in TRAVERSAL,
                    )
                )
                time.sleep(0.17)
                response = post(dict(uid="999", map="mp_colony", nonce="observer", emote=""))
                received = next(p for p in response["peers"] if p["uid"] == uid)
                self.assertEqual(received["emote"], emote)
                self.assertEqual(received["traversal"], emote in TRAVERSAL)
                self.assertGreaterEqual(received["age"], 0.15)
        finally:
            srv.shutdown()
            srv.server_close()
            thread.join()

    def test_http_auth_and_invalid_input(self):
        srv = Server(("127.0.0.1", 0), "test-secret")
        thread = threading.Thread(target=srv.serve_forever, daemon=True)
        thread.start()
        try:
            url = f"http://127.0.0.1:{srv.server_port}/sync"
            token = "test-secret"
            for body, key, expected in [
                (b"{}", "bad", 401),
                (b"[]", token, 400),
                (b"x" * 8193, token, 413),
            ]:
                req = urllib.request.Request(url, body, {"Authorization": "Bearer " + key})
                with self.assertRaises(urllib.error.HTTPError) as error:
                    urllib.request.urlopen(req)
                self.assertEqual(error.exception.code, expected)
            data = json.dumps(
                dict(uid="123", map="mp_colony", nonce="one", emote="bbd_traversal")
            ).encode()
            req = urllib.request.Request(url, data, {"Authorization": "Bearer "+token})
            self.assertEqual(
                json.load(urllib.request.urlopen(req))["peers"][0]["emote"], "bbd_traversal"
            )
        finally:
            srv.shutdown()
            srv.server_close()
            thread.join()


if __name__ == "__main__":
    unittest.main()
