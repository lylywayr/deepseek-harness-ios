#!/usr/bin/env python3
"""Deterministic simulator screenshot artifact gate; no image editing."""
import hashlib, pathlib, struct, sys, zlib
root=pathlib.Path(sys.argv[1]); pngs=sorted(root.rglob('*.png'))
assert len(pngs)==28, f'expected 28 PNGs, got {len(pngs)}'
assert len({hashlib.sha256(p.read_bytes()).hexdigest() for p in pngs})==28, 'duplicate PNG evidence'
for p in pngs:
    b=p.read_bytes(); assert b[:8]==b'\x89PNG\r\n\x1a\n'
    w,h=struct.unpack('>II',b[16:24]); assert (w,h) in ((1170,2532),(1290,2796)), (p,w,h)
    assert p.stat().st_size>10000
# The keyboard artifact must contain real lower-screen raster activity; the
# onboarding card is a static light card and cannot satisfy this variance gate.
k=[p for p in pngs if p.name=='keyboard-390x844-light.png']
assert k, 'missing 390 keyboard artifact'
b=k[0].read_bytes(); pos=8; idat=b''
while pos<len(b):
    n=struct.unpack('>I',b[pos:pos+4])[0]; typ=b[pos+4:pos+8]; data=b[pos+8:pos+8+n]; pos+=12+n
    if typ==b'IDAT': idat+=data
raw=zlib.decompress(idat); w,h=struct.unpack('>II',b[16:24]); stride=w*4+1
rows=[raw[i*stride+1:(i+1)*stride] for i in range(int(h*.70),h)]
vals=[x for row in rows for x in row]
assert len(set(vals))>32 and max(vals)-min(vals)>80, 'keyboard lower raster lacks real key activity'
print(f'PASS: {len(pngs)} PNGs, 28 unique, dimensions valid, keyboard raster gate passed')
