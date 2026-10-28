import unittest
from relay import Room


class SyncEmoteTests(unittest.TestCase):
    def setUp(self):
        self.now = 100.0
        self.room = Room(lambda: self.now)
        self.lead = dict(uid='123', map='mp_colony', nonce='lead', emote='griddy_traversal', traversal=True)
        self.room.sync(self.lead)
        self.now += 2
        self.follower = dict(self.lead, uid='456', nonce='join', sync_uid='123', sync_nonce='lead')

    def test_join_copies_phase_and_survives_leader_stopping(self):
        status, body = self.room.sync(self.follower)
        self.assertEqual(status, 200)
        self.assertEqual({p['age'] for p in body['peers']}, {2.0})
        self.now += 1
        self.room.sync(dict(self.lead, nonce='stop', emote='', traversal=False))
        status, body = self.room.sync(self.follower)
        self.assertEqual(status, 200)
        self.assertEqual(next(p['age'] for p in body['peers'] if p['uid'] == '456'), 3.0)

    def test_retry_does_not_restart_or_recouple(self):
        self.room.sync(self.follower)
        self.now += 1
        self.room.sync(dict(self.lead, nonce='next'))
        self.assertEqual(self.room.sync(self.follower)[0], 200)
        self.assertEqual(self.room.peers['456']['start'], 100.0)

    def test_shared_timeline_and_only_original_music_source(self):
        status, body = self.room.sync(self.follower)
        peers = {p['uid']: p for p in body['peers']}
        self.assertEqual(status, 200)
        self.assertEqual(peers['123']['timeline'], peers['456']['timeline'])
        self.assertTrue(peers['123']['music'])
        self.assertFalse(peers['456']['music'])
        self.now += 1
        _, body = self.room.sync(dict(self.follower, uid='789', sync_uid='456', sync_nonce='join'))
        peers = {p['uid']: p for p in body['peers']}
        self.assertEqual(len({p['timeline'] for p in peers.values()}), 1)
        self.assertFalse(peers['789']['music'])
        self.now += 1
        self.room.sync(dict(self.lead, nonce='stop', emote='', traversal=False))
        _, body = self.room.sync(self.follower)
        self.assertFalse(next(p['music'] for p in body['peers'] if p['uid'] == '456'))
        self.now += 1
        _, body = self.room.sync(dict(self.lead, uid='456', nonce='ordinary'))
        restarted = next(p for p in body['peers'] if p['uid'] == '456')
        self.assertTrue(restarted['music'])
        self.assertNotEqual(restarted['timeline'], peers['456']['timeline'])

    def test_reject_stale_changed_missing_or_wrong_map_target(self):
        for patch in ({'sync_nonce': 'wrong'}, {'sync_uid': '999'}, {'map': 'mp_angel_city'},
                      {'emote': 'bbd_traversal'}, {'traversal': False}):
            self.assertEqual(self.room.sync(dict(self.follower, **patch))[0], 409)
            self.assertNotIn('456', self.room.peers)
        self.now += 6
        self.assertEqual(self.room.sync(self.follower)[0], 409)

    def test_reject_bad_target_fields(self):
        for patch in ({'sync_uid': None}, {'sync_nonce': None}, {'sync_uid': '456'},
                      {'sync_uid': '0'}, {'sync_nonce': []}, {'sync_uid': {}},
                      {'sync_nonce': 'bad nonce'}, {'emote': '', 'traversal': False}):
            with self.assertRaises(ValueError):
                self.room.sync(dict(self.follower, **patch))
        for missing in ('sync_uid', 'sync_nonce'):
            data = self.follower.copy()
            del data[missing]
            with self.assertRaises(ValueError):
                self.room.sync(data)

    def test_sync_chain_and_normal_restart(self):
        self.room.sync(self.follower)
        self.now += 1
        third = dict(self.follower, uid='789', sync_uid='456', sync_nonce='join')
        self.assertEqual(self.room.sync(third)[0], 200)
        self.assertEqual(self.room.peers['789']['start'], 100.0)
        self.now += 1
        self.room.sync(dict(self.lead, uid='789', nonce='ordinary'))
        self.assertEqual(self.room.peers['789']['start'], 104.0)


if __name__ == '__main__':
    unittest.main()
