"""
Rattache des gyrophares (os sirenN) à de nouveaux extras dans un modèle de véhicule exporté en XML par CodeWalker.

- Ajoute les os extra_N (enfants de chassis, sans décalage) et place chaque gyrophare choisi sous son extra.
- Nouvel ordre des os : os d'origine (sans les gyrophares déplacés), puis chaque extra suivi de ses gyrophares
  (le jeu veut chaque parent avant ses enfants).
- Les sommets ne sont pas touchés : seules les listes BoneIDs des maillages (n° d'os de chaque indice de
  sommet) sont renumérotées, ainsi que BoneTransforms et le nombre d'os des modèles (Unknown1).
- Position / rotation locale des gyrophares recalculées : leur position réelle ne bouge pas (vérifié).

Usage : add_extras.py entree.yft.xml sortie.yft.xml "1:1,2,3" "2:11,12"
"""
import re
import sys
import xml.etree.ElementTree as ET


def elf(s):
    h = 0
    for c in s.encode():
        h = ((h << 4) + c) & 0xFFFFFFFF
        x = h & 0xF0000000
        if x:
            h ^= x >> 24
        h &= ~x & 0xFFFFFFFF
    return h


def bone_tag(name):
    """Tag d'os de RAGE : ElfHash du nom en majuscules (vérifié sur tous les os existants)."""
    return (elf(name.upper()) % 0xFE8F) + 0x170


def extra_name(n):
    return 'extra_ten' if n == 10 else 'extra_%d' % n


# ---- quaternions (x, y, z, w) ----
def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz)


def qconj(q):
    return (-q[0], -q[1], -q[2], q[3])


def qrot(q, v):
    r = qmul(qmul(q, (v[0], v[1], v[2], 0.0)), qconj(q))
    return (r[0], r[1], r[2])


def fmt(v):
    s = repr(float(v))
    return '0' if s in ('0.0', '-0.0') else s


def local(b):
    t, r = b.find('Translation'), b.find('Rotation')
    return ((float(t.get('x')), float(t.get('y')), float(t.get('z'))),
            (float(r.get('x')), float(r.get('y')), float(r.get('z')), float(r.get('w'))))


def globals_of(bones):
    """Position / rotation réelles (repère du modèle) : parent * local, parents avant enfants"""
    out = []
    for i, b in enumerate(bones):
        pos, rot = local(b)
        parent = int(b.find('ParentIndex').get('value'))
        if parent < 0:
            out.append((pos, rot))
        else:
            if parent >= i:
                raise SystemExit('os %d avant son parent %d' % (i, parent))
            ppos, prot = out[parent]
            rp = qrot(prot, pos)
            out.append(((ppos[0] + rp[0], ppos[1] + rp[1], ppos[2] + rp[2]), qmul(prot, rot)))
    return out


def main():
    src, dst = sys.argv[1], sys.argv[2]
    groups = []
    for spec in sys.argv[3:]:
        extra, sirens = spec.split(':')
        groups.append((int(extra), [int(x) for x in sirens.split(',') if x]))

    text = open(src, encoding='utf-8').read()
    start = text.index('<Skeleton>')
    end = text.index('</Skeleton>', start) + len('</Skeleton>')
    skeleton = ET.fromstring(text[start:end])
    bones_el = skeleton.find('Bones')
    old = list(bones_el)
    by_name = {b.findtext('Name'): i for i, b in enumerate(old)}
    old_glob = globals_of(old)
    old_parent = [int(b.find('ParentIndex').get('value')) for b in old]
    chassis = by_name['chassis']
    report = []

    # Gyrophares à déplacer (présents, sans enfants)
    moved = {}
    for extra, sirens in groups:
        if extra_name(extra) in by_name:
            raise SystemExit('%s existe déjà dans ce modèle' % extra_name(extra))
        for n in sirens:
            i = by_name.get('siren%d' % n)
            if i is None:
                report.append('  siren%d absent du modèle : ignoré' % n)
            elif i in old_parent:
                raise SystemExit('siren%d a des os enfants : non déplacé' % n)
            else:
                moved[i] = extra

    # Nouvel ordre : (ancien index ou ('extra', n))
    order = [i for i in range(len(old)) if i not in moved]
    for extra, _ in groups:
        order.append(('extra', extra))
        order.extend(i for i in sorted(moved) if moved[i] == extra)
    new_index = {}
    for pos, key in enumerate(order):
        new_index[key] = pos

    template = old[by_name['extra_ten']] if 'extra_ten' in by_name else old[chassis]
    new_bones, new_glob = [], []
    for pos, key in enumerate(order):
        if isinstance(key, tuple):
            name = extra_name(key[1])
            el = ET.fromstring(ET.tostring(template))
            el.find('Name').text = name
            el.find('Tag').set('value', str(bone_tag(name)))
            el.find('ParentIndex').set('value', str(new_index[chassis]))
            el.find('Translation').attrib.update({'x': '0', 'y': '0', 'z': '0'})
            el.find('Rotation').attrib.update({'x': '0', 'y': '0', 'z': '0', 'w': '1'})
            el.find('Scale').attrib.update({'x': '1', 'y': '1', 'z': '1'})
            new_glob.append(old_glob[chassis]) # extra au même endroit que chassis
            report.append('  %s : tag %s, os %d' % (name, el.find('Tag').get('value'), pos))
        else:
            el = old[key]
            if key in moved:
                extra_pos = new_index[('extra', moved[key])]
                epos, erot = new_glob[extra_pos]
                gpos, grot = old_glob[key]
                inv = qconj(erot)
                lpos = qrot(inv, (gpos[0] - epos[0], gpos[1] - epos[1], gpos[2] - epos[2]))
                lrot = qmul(inv, grot)
                report.append('  %s : os %d -> %d, parent %s -> %s' % (
                    el.findtext('Name'), key, pos, old[old_parent[key]].findtext('Name'), extra_name(moved[key])))
                el.find('ParentIndex').set('value', str(extra_pos))
                el.find('Translation').attrib.update({'x': fmt(lpos[0]), 'y': fmt(lpos[1]), 'z': fmt(lpos[2])})
                el.find('Rotation').attrib.update({'x': fmt(lrot[0]), 'y': fmt(lrot[1]), 'z': fmt(lrot[2]), 'w': fmt(lrot[3])})
            else:
                p = old_parent[key]
                el.find('ParentIndex').set('value', str(new_index[p] if p >= 0 else -1))
            new_glob.append(old_glob[key])
        el.find('Index').set('value', str(pos))
        new_bones.append(el)

    # SiblingIndex : prochain os du même parent
    parents = [int(b.find('ParentIndex').get('value')) for b in new_bones]
    for i, b in enumerate(new_bones):
        b.find('SiblingIndex').set('value', str(next((j for j in range(i + 1, len(new_bones)) if parents[j] == parents[i]), -1)))
    for b in list(bones_el):
        bones_el.remove(b)
    for b in new_bones:
        bones_el.append(b)

    # Contrôle : chaque os garde sa position réelle
    check = globals_of(new_bones)
    worst = 0.0
    for pos, key in enumerate(order):
        ref = new_glob[pos]
        worst = max(worst, max(abs(a - c) for a, c in zip(ref[0], check[pos][0])))

    # Squelette réécrit (mise en forme de CodeWalker)
    ET.indent(skeleton, space=' ', level=0)
    base_indent = text[text.rfind('\n', 0, start) + 1:start]
    body = ET.tostring(skeleton, encoding='unicode').replace('\n', '\n' + base_indent)
    out = text[:start] + body + text[end:]

    # BoneIDs de tous les maillages : ancien n° d'os -> nouveau
    remap = {i: new_index[i] for i in range(len(old))}

    def fix_ids(m):
        ids = [int(x) for x in m.group(1).replace(',', ' ').split()]
        return '<BoneIDs>' + ', '.join(str(remap[i]) for i in ids) + '</BoneIDs>'

    out, n_ids = re.subn(r'<BoneIDs>([^<]*)</BoneIDs>', fix_ids, out)

    # BoneTransforms : une matrice par os, dans le nouvel ordre (identité pour les extras)
    bt_start = out.index('<BoneTransforms')
    bt_end = out.index('</BoneTransforms>', bt_start)
    head_end = out.index('>', bt_start) + 1
    blocks = re.findall(r'(\s*<Item>.*?</Item>)', out[head_end:bt_end], flags=re.S)
    if len(blocks) != len(old):
        raise SystemExit('BoneTransforms : %d matrices pour %d os' % (len(blocks), len(old)))
    ident = re.sub(r'<Item>.*?</Item>', '<Item>\n   1 0 0 0\n   0 1 0 0\n   0 0 1 0\n  </Item>', blocks[0], flags=re.S)
    new_blocks = [ident if isinstance(key, tuple) else blocks[key] for key in order]
    out = out[:head_end] + ''.join(new_blocks) + out[bt_end:]

    # Nombre d'os des modèles
    out = out.replace('<Unknown1 value="%d" />' % len(old), '<Unknown1 value="%d" />' % len(new_bones))

    open(dst, 'w', encoding='utf-8', newline='\n').write(out)
    print('%s : %d os (+%d extras), %d listes BoneIDs renumérotées, écart de position maxi %.2e m' % (
        dst.split('/')[-1], len(new_bones), len(groups), n_ids, worst))
    print('\n'.join(report))


if __name__ == '__main__':
    main()
