#!/usr/bin/env python3
"""Exercise actual base/patch artifacts: embedded metadata equals their sidecars."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

compiler = str(Path(sys.argv[1]).resolve())
fixture = Path(sys.argv[2]).read_text()


def embedded(ir, name):
    match = re.search(r'@' + name + r' = constant \[\d+ x i8\] c"([^"\n]*)"', ir)
    assert match, f"missing embedded {name}"
    value = re.sub(r'\\([0-9A-Fa-f]{2})', lambda m: chr(int(m[1], 16)), match[1])
    assert value.endswith('\0'), f"{name} not terminated"
    return value[:-1]


with tempfile.TemporaryDirectory(prefix='march-hcr-metadata-') as directory:
    root = Path(directory)
    env = dict(os.environ, HOME=str(root / 'home'))
    (root / 'home').mkdir()
    schemas = []
    for patch in (False, True):
        source = root / ('patch.march' if patch else 'base.march')
        source.write_text(fixture)
        output = root / ('patch.so' if patch else 'base')
        cmd = [compiler, '--compile', '--emit-llvm', '--hot-reload', 'SchemaProbe',
               '-o', str(output), str(source)]
        if patch:
            cmd.append('--compile-so')
        subprocess.run(cmd, env=env, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        ir = source.with_suffix('.ll').read_text()
        for symbol, suffix in [('__march_hcr_schemas', '.schemas.json'),
                               ('__march_hcr_manifest', '.hcr_manifest')]:
            actual = embedded(ir, symbol)
            assert actual == Path(str(output) + suffix).read_text(), symbol + ' differs from sidecar'
        schema = json.loads(embedded(ir, '__march_hcr_schemas'))
        assert sorted(f['name'] for f in schema['Counter']['state_fields']) == ['label', 'value']
        schemas.append(schema)
    assert schemas[0] == schemas[1], 'base and patch schema disagree'
    # Rebuild identical sources from separate directories, with cold and warm caches.
    # Emit-only manifests intentionally omit the artifact CAS key.
    deterministic = []
    for location in ('left', 'right'):
        cwd = root / location
        cwd.mkdir()
        home = cwd / 'home'
        home.mkdir()
        source = cwd / 'probe.march'
        source.write_text(fixture)
        for _ in range(2):
            subprocess.run([compiler, '--emit-llvm', '--hot-reload', 'SchemaProbe',
                            str(source)], cwd=cwd, env=dict(os.environ, HOME=str(home)),
                           check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            ir = source.with_suffix('.ll').read_text()
            deterministic.append(tuple(embedded(ir, symbol) for symbol in
                                       ('__march_hcr_schemas', '__march_hcr_manifest')))
    assert all(value == deterministic[0] for value in deterministic), 'metadata is nondeterministic'
print('base and patch metadata match sidecars; cold/warm and directory metadata agree')
