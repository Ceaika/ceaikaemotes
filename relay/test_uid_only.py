import http.client
import json
import threading
import unittest
from relay import Server


class UIDOnlyTests(unittest.TestCase):
    def setUp(self):
        self.server = Server(('127.0.0.1', 0), 'test-room-key')
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def post(self, path, data, key='test-room-key'):
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=5)
        try:
            connection.request('POST', path, json.dumps(data), {'Authorization': 'Bearer ' + key})
            response = connection.getresponse()
            return response.status, json.loads(response.read())
        finally:
            connection.close()

    def test_uid_sync_without_ea_or_sessions(self):
        data = dict(uid='123', map='mp_colony', nonce='one', emote='emote_oj')
        status, body = self.post('/sync', data)
        self.assertEqual(status, 200)
        self.assertEqual(body['peers'][0]['uid'], '123')
        self.assertFalse(hasattr(self.server, 'sessions'))
        # Deliberately document that another claimed UID is accepted with the same key.
        self.assertEqual(self.post('/sync', dict(data, uid='456'))[0], 200)

    def test_auth_removed_and_credentials_rejected_as_sync_fields(self):
        self.assertEqual(self.post('/auth', {'uid': '123', 'code': 'dummy-code'})[0], 404)
        data = dict(uid='123', map='mp_colony', nonce='one', emote='')
        self.assertEqual(self.post('/sync', data, 'old-session-token')[0], 401)
        self.assertEqual(self.post('/sync', dict(data, code='dummy-code'))[0], 400)
        del data['uid']
        self.assertEqual(self.post('/sync', data)[0], 400)

    def test_sync_phase_over_http(self):
        clock = [100.0]
        self.server.room.clock = lambda: clock[0]
        lead = dict(uid='123', map='mp_colony', nonce='lead', emote='emote_oj')
        self.assertEqual(self.post('/sync', lead)[0], 200)
        clock[0] += 2
        follower = dict(lead, uid='456', nonce='join', sync_uid='123', sync_nonce='lead')
        status, body = self.post('/sync', follower)
        self.assertEqual(status, 200)
        self.assertEqual({p['age'] for p in body['peers']}, {2.0})
        self.assertEqual(self.post('/sync', dict(follower, uid='789', sync_nonce='stale'))[0], 409)


if __name__ == '__main__':
    unittest.main()
