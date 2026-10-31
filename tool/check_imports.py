#!/usr/bin/env python3
"""Kiểm tra mọi import/export nội bộ đều trỏ tới file TỒN TẠI (chạy trước khi push).
Dùng:  python3 tool/check_imports.py   → thoát mã 1 nếu thiếu file."""
import glob, os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
bad = []
for f in glob.glob('lib/**/*.dart', recursive=True) + glob.glob('test/**/*.dart', recursive=True):
    for m in re.finditer(r"^(?:import|export)\s+'([^']+)'", open(f, encoding='utf-8').read(), re.M):
        p = m.group(1)
        if p.startswith('dart:') or (p.startswith('package:') and not p.startswith('package:mybike_app/')):
            continue
        t = 'lib/' + p[len('package:mybike_app/'):] if p.startswith('package:mybike_app/') \
            else os.path.normpath(os.path.join(os.path.dirname(f), p))
        if not os.path.exists(t):
            bad.append((f, t))
for f, t in sorted(set(bad)):
    print(f'THIẾU: {t}   (được import bởi {f})')
print('OK — mọi import đều có file.' if not bad else f'{len(set(bad))} import trỏ tới file không tồn tại.')
sys.exit(1 if bad else 0)
