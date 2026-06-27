#!/usr/bin/env python3
import sys, crypt
shadow = sys.argv[1]
h = crypt.crypt('root', crypt.mksalt(crypt.METHOD_SHA512))
with open(shadow) as f: lines = f.readlines()
with open(shadow, 'w') as f:
    for l in lines:
        if l.startswith('root:'):
            parts = l.split(':')
            parts[1] = h
            l = ':'.join(parts)
        f.write(l)
