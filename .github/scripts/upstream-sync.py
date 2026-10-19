#!/usr/bin/env python3
"""Fast-forward the mirror with an atomic, non-forced ref update; never merge PRs."""
import json
import os
import subprocess

UPSTREAM = 'krishhgg/Insomnia'


def api(path, method='GET', **fields):
    command = ['gh', 'api', '-X', method, path]
    if fields:
        command += ['--input', '-']
    result = subprocess.run(command, input=json.dumps(fields) if fields else None,
                            text=True, capture_output=True, check=True)
    return json.loads(result.stdout) if result.stdout.strip() else None


def synchronize(repo, call=api):
    prefix = f'repos/{repo}'
    upstream = call(f'repos/{UPSTREAM}/commits/main')['sha']
    mirror = call(f'{prefix}/git/ref/heads/main')['object']['sha']
    if mirror != upstream:
        comparison = call(f'{prefix}/compare/{mirror}...{upstream}')
        if comparison['status'] != 'ahead' or comparison['behind_by'] != 0:
            raise RuntimeError('main diverged from upstream: refusing to overwrite history')
        # force=false is enforced by GitHub even if main changes after comparison.
        call(f'{prefix}/git/refs/heads/main', 'PATCH', sha=upstream, force=False)
        print(f'main fast-forwarded: {mirror} -> {upstream}')
    else:
        print('main already matches upstream')

    custom = call(f'{prefix}/git/ref/heads/custom')['object']['sha']
    difference = call(f'{prefix}/compare/{custom}...{upstream}')
    if difference['ahead_by'] == 0:
        print('custom already contains upstream; no PR needed')
        return None

    owner = repo.split('/')[0]
    pulls = call(f'{prefix}/pulls?state=open&base=custom&head={owner}:main&per_page=100')
    if len(pulls) > 1:
        raise RuntimeError('Multiple main -> custom PRs already exist; resolve manually')
    if pulls:
        pr = pulls[0]
        print(f'Reusing PR #{pr["number"]}')
    else:
        # Compare API returns at most 250 commits; always link the complete diff.
        commits = difference.get('commits', [])
        lines = [f'- {c["sha"][:12]} {c["commit"]["message"].splitlines()[0]}' for c in commits]
        body = ('## Upstream update\n\n'
                f'{difference["ahead_by"]} upstream commits not yet in custom.\n\n'
                + '\n'.join(lines) + '\n\n'
                f'[Complete comparison](https://github.com/{repo}/compare/custom...main)\n\n'
                '## Main changes and conflict review\n\n'
                'Commit subjects above describe upstream changes; review the complete diff, '
                'especially recovery journal, backstop, session lifecycle and power management. '
                'GitHub computes mergeability after opening this PR; CI tests the merge ref. '
                'If conflicts exist, leave this PR open and resolve them on a separate integration '
                'branch based on custom. Never commit resolutions to mirror main. '
                'Product decisions require the owner. No automatic merge.\n')
        pr = call(f'{prefix}/pulls', 'POST', title='Sync upstream main into custom',
                  head='main', base='custom', body=body)
        print(f'Created PR #{pr["number"]}')
    details = call(f'{prefix}/pulls/{pr["number"]}')
    if details.get('mergeable') is False:
        print(f'PR #{pr["number"]} has conflicts; manual resolution required; CI will fail closed')
    # Dispatch explicitly; token-created PR events are not a reliable CI trigger.
    # The separate CI status job binds its result to both captured head/base SHAs.
    call(f'{prefix}/actions/workflows/fork-ci.yml/dispatches', 'POST',
         ref='custom', inputs={'pr': str(pr['number'])})
    print(f'CI dispatched for PR #{pr["number"]}; automatic merge is disabled')
    return pr['number']


if __name__ == '__main__':
    synchronize(os.environ['GH_REPO'])
