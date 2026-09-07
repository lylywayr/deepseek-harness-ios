#!/usr/bin/env python3
"""Deterministic simulator screenshot artifact gate; no image editing."""
import hashlib, pathlib, struct, sys
from collections import defaultdict
root=pathlib.Path(sys.argv[1]); pngs=sorted(root.rglob('*.png'))
assert len(pngs)==26, f'expected 26 PNGs, got {len(pngs)}'
groups=defaultdict(list)
for p in pngs: groups[hashlib.sha256(p.read_bytes()).hexdigest()].append(str(p.relative_to(root)))
duplicates=[paths for paths in groups.values() if len(paths)>1]
if duplicates:
    print("DUPLICATE_SCREENSHOT_GROUPS:")
    for paths in duplicates: print("  " + " == ".join(paths))
    raise AssertionError('duplicate PNG evidence')
assert len(groups)==26, 'duplicate PNG evidence'
for p in pngs:
    b=p.read_bytes(); assert b[:8]==b'\x89PNG\r\n\x1a\n'
    w,h=struct.unpack('>II',b[16:24]); assert (w,h) in ((1170,2532),(1290,2796)), (p,w,h)
    assert p.stat().st_size>10000
print(f'PASS: {len(pngs)} PNGs, unique, dimensions valid; keyboard raster is not a simulator gate')
