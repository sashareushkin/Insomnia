"""No GitHub writes: exercise sync with in-memory API responses."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
from types import SimpleNamespace
import json
import subprocess

spec = importlib.util.spec_from_file_location('sync', Path(__file__).with_name('upstream-sync.py'))
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class FakeAPI:
    def __init__(self, mirror='old', status='ahead', integrated=False, existing=False, conflict=False):
        self.mirror, self.status, self.integrated = mirror, status, integrated
        self.prs = [{'number': 7}] if existing else []
        self.writes = []
        self.conflict = conflict

    def __call__(self, path, method='GET', **fields):
        if method != 'GET':
            self.writes.append((path, method, fields))
            if method == 'PATCH':
                assert fields['force'] is False
                self.mirror = fields['sha']
            if path.endswith('/pulls'):
                self.prs = [{'number': 7}]
                return self.prs[0]
            return None
        if path.endswith('/commits/main'): return {'sha': 'new'}
        if path.endswith('/git/ref/heads/main'): return {'object': {'sha': self.mirror}}
        if path.endswith('/git/ref/heads/custom'): return {'object': {'sha': 'custom'}}
        if '/compare/custom...' in path:
            return {'ahead_by': 0 if self.integrated else 1, 'commits': [
                {'sha': 'new', 'commit': {'message': 'Recovery fix\nDetails'}}]}
        if '/compare/' in path:
            return {'status': self.status, 'behind_by': 0 if self.status == 'ahead' else 1}
        if '/pulls?' in path: return self.prs
        if '/pulls/7' in path: return {'mergeable': not self.conflict}
        raise AssertionError(path)


class SyncTests(unittest.TestCase):
    def test_transport_preserves_non_forced_boolean(self):
        with patch.object(sync.subprocess, 'run', return_value=SimpleNamespace(stdout='{}')) as run:
            sync.api('repos/owner/fork/git/refs/heads/main', 'PATCH', sha='new', force=False)
            self.assertIs(json.loads(run.call_args.kwargs['input'])['force'], False)

    def test_transport_reports_github_permission_error(self):
        error = subprocess.CalledProcessError(1, ['gh', 'api'], stderr='HTTP 403: workflows permission required')
        with patch.object(sync.subprocess, 'run', side_effect=error):
            with self.assertRaisesRegex(RuntimeError, 'HTTP 403: workflows permission required'):
                sync.api('repos/owner/fork/git/refs/heads/main', 'PATCH', sha='new', force=False)

    def test_no_updates_no_writes(self):
        fake = FakeAPI(mirror='new', integrated=True)
        self.assertIsNone(sync.synchronize('owner/fork', fake))
        self.assertEqual(fake.writes, [])

    def test_fast_forward_create_and_dispatch(self):
        fake = FakeAPI()
        self.assertEqual(sync.synchronize('owner/fork', fake), 7)
        self.assertEqual([m for _, m, _ in fake.writes], ['PATCH', 'POST', 'POST'])
        self.assertEqual(fake.writes[-1][2]['inputs'], {'pr': '7'})

    def test_retry_does_not_duplicate_pr(self):
        fake = FakeAPI()
        sync.synchronize('owner/fork', fake)
        sync.synchronize('owner/fork', fake)
        self.assertEqual(sum(p.endswith('/pulls') for p, _, _ in fake.writes), 1)
        self.assertEqual(sum(m == 'PATCH' for _, m, _ in fake.writes), 1)

    def test_divergence_and_ahead_fail_without_writes(self):
        for status in ('diverged', 'behind'):
            fake = FakeAPI(status=status)
            with self.assertRaises(RuntimeError): sync.synchronize('owner/fork', fake)
            self.assertEqual(fake.writes, [])

    def test_existing_conflicting_pr_is_kept_open(self):
        fake = FakeAPI(mirror='new', existing=True, conflict=True)
        self.assertEqual(sync.synchronize('owner/fork', fake), 7)
        self.assertEqual(len(fake.writes), 1)
        self.assertIn('/dispatches', fake.writes[0][0])

    def test_multiple_existing_prs_fail_closed(self):
        fake = FakeAPI(mirror='new', existing=True)
        fake.prs.append({'number': 8})
        with self.assertRaises(RuntimeError): sync.synchronize('owner/fork', fake)
        self.assertEqual(fake.writes, [])

    def test_api_failure_stops_before_pr(self):
        fake = FakeAPI()
        def fail(path, method='GET', **fields):
            if method == 'PATCH': raise RuntimeError('ref moved or token denied')
            return fake(path, method, **fields)
        with self.assertRaises(RuntimeError): sync.synchronize('owner/fork', fail)
        self.assertEqual(fake.writes, [])


if __name__ == '__main__': unittest.main()
