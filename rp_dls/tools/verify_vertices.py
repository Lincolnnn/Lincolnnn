import sys, xml.etree.ElementTree as ET
SIZES = {'Position': 3, 'BlendWeights': 4, 'BlendIndices': 4, 'Normal': 3, 'Colour0': 4, 'Colour1': 4,
         'TexCoord0': 2, 'TexCoord1': 2, 'TexCoord2': 2, 'TexCoord3': 2, 'TexCoord4': 2, 'TexCoord5': 2,
         'TexCoord6': 2, 'TexCoord7': 2, 'Tangent': 4}
def bindings(path):
    root = ET.parse(path).getroot()
    names = [b.findtext('Name') for b in root.find('Drawable').find('Skeleton').find('Bones')]
    out = []
    for g in root.iter('Item'):
        vb = g.find('VertexBuffer'); ids = g.findtext('BoneIDs')
        if vb is None or ids is None: continue
        layout = [c.tag for c in vb.find('Layout')]
        if 'BlendIndices' not in layout:
            out.append(None); continue
        off = 0; offs = {}
        for t in layout:
            offs[t] = off; off += SIZES[t]
        ids = [int(x) for x in ids.replace(',', ' ').split()]
        per = []
        for line in vb.findtext('Data').strip().splitlines():
            v = line.split()
            w = v[offs['BlendWeights']:offs['BlendWeights'] + 4]
            idx = v[offs['BlendIndices']:offs['BlendIndices'] + 4]
            per.append(tuple(sorted(names[ids[int(i)]] for wi, i in zip(w, idx) if wi != '0')))
        out.append(per)
    return out
a, b = bindings(sys.argv[1]), bindings(sys.argv[2])
assert len(a) == len(b), (len(a), len(b))
diff = sum(1 for x, y in zip(a, b) if x != y)
verts = sum(len(x) for x in a if x)
print(sys.argv[1].split('/')[-1], ': maillages', len(a), 'sommets', verts, '| maillages différents :', diff)
