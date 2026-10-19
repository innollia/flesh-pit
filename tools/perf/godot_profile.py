"""Function-level GDScript profile captures for flesh-pit, without a custom
engine build: Godot's own script profiler over its remote-debug protocol.

The game is started with --remote-debug pointing at this script, which then
turns the "servers" profiler on (script functions: calls, self and total
time per frame) and records every frame. tests/bench_play.gd marks its
phases with EngineDebugger messages ("bench:phase"), so frames are grouped
per phase. Run it only on an isolated copy (docs/operations.md).

  capture   run a bench script, write a capture JSON
  hotspots  slowest functions per phase (self or total ms per frame)
  hitches   the worst frames per phase and the functions that filled them
  compare   two captures, per function and phase: what got slower/faster

  python tools/perf/godot_profile.py capture --project <iso>/game --out before.json
  python tools/perf/godot_profile.py hotspots before.json --phase tunnel_walk
  python tools/perf/godot_profile.py compare before.json after.json --phase tunnel_walk

The editor binary runs GDScript with debug checks, so absolute times are
higher than an exported release build; compare captures from the same
binary, machine and resolution only.
"""
import argparse
import json
import os
import socket
import struct
import subprocess
import sys
import threading
import time

# --- Variant decoding (core/io/marshalls.cpp, Godot 4) -----------------------

FLAG_64 = 1 << 16
FLOATS = {5: 2, 7: 4, 9: 3, 11: 6, 12: 4, 14: 4, 15: 4, 16: 6, 17: 9, 18: 12, 19: 16}
INTS = {6: 2, 8: 4, 10: 3, 13: 4}


class Reader:
    def __init__(self, data):
        self.d = data
        self.p = 0

    def u32(self):
        v = struct.unpack_from('<I', self.d, self.p)[0]
        self.p += 4
        return v

    def i32(self):
        v = struct.unpack_from('<i', self.d, self.p)[0]
        self.p += 4
        return v

    def i64(self):
        v = struct.unpack_from('<q', self.d, self.p)[0]
        self.p += 8
        return v

    def f32(self):
        v = struct.unpack_from('<f', self.d, self.p)[0]
        self.p += 4
        return v

    def f64(self):
        v = struct.unpack_from('<d', self.d, self.p)[0]
        self.p += 8
        return v

    def string(self):
        n = self.u32()
        s = self.d[self.p:self.p + n].decode('utf-8', 'replace')
        self.p += n + ((4 - n % 4) % 4)
        return s

    def container_type(self, kind):
        # 1 builtin type, 2 class name, 3 script path
        if kind == 1:
            self.u32()
        elif kind in (2, 3):
            self.string()

    def variant(self):
        header = self.u32()
        t = header & 0xFF
        if t == 0:
            return None
        if t == 1:
            return self.u32() != 0
        if t == 2:
            return self.i64() if header & FLAG_64 else self.i32()
        if t == 3:
            return self.f64() if header & FLAG_64 else self.f32()
        if t in (4, 21):
            return self.string()
        if t in FLOATS:
            return [self.f64() if header & FLAG_64 else self.f32() for _ in range(FLOATS[t])]
        if t in INTS:
            return [self.i32() for _ in range(INTS[t])]
        if t == 20:
            return [self.f32() for _ in range(4)]
        if t == 22:  # NodePath
            names = self.u32()
            if names & 0x80000000:
                names &= 0x7FFFFFFF
                subs = self.u32()
                self.u32()
                return '/'.join(self.string() for _ in range(names + subs))
            return ''
        if t == 23:
            return self.i64()
        if t == 24:
            if header & FLAG_64:
                return self.i64()
            cls = self.string()
            if cls == '':
                return None
            for _ in range(self.u32()):
                self.string()
                self.variant()
            return cls
        if t == 25:
            return None
        if t == 26:
            name = self.string()
            self.i64()
            return name
        if t == 27:
            self.container_type((header >> 16) & 3)
            self.container_type((header >> 18) & 3)
            n = self.u32() & 0x7FFFFFFF
            out = {}
            for _ in range(n):
                k = self.variant()
                out[json.dumps(k) if isinstance(k, (list, dict)) else k] = self.variant()
            return out
        if t == 28:
            self.container_type((header >> 16) & 3)
            n = self.u32() & 0x7FFFFFFF
            return [self.variant() for _ in range(n)]
        if t == 29:
            n = self.u32()
            b = self.d[self.p:self.p + n]
            self.p += n + ((4 - n % 4) % 4)
            return list(b)
        if t == 30:
            return [self.i32() for _ in range(self.u32())]
        if t == 31:
            return [self.i64() for _ in range(self.u32())]
        if t == 32:
            return [self.f32() for _ in range(self.u32())]
        if t == 33:
            return [self.f64() for _ in range(self.u32())]
        if t == 34:
            return [self.string() for _ in range(self.u32())]
        if t in (35, 36, 37, 38):
            k = {35: 2, 36: 3, 37: 4, 38: 4}[t]
            n = self.u32()
            wide = header & FLAG_64 and t != 37
            return [[self.f64() if wide else self.f32() for _ in range(k)] for _ in range(n)]
        raise ValueError('unknown variant type %d at %d' % (t, self.p - 4))


def encode(v):
    """Enough of the encoder for messages we send: str, int, bool, list."""
    if isinstance(v, bool):
        return struct.pack('<II', 1, 1 if v else 0)
    if isinstance(v, int):
        return struct.pack('<Iq', 2 | FLAG_64, v)
    if isinstance(v, str):
        b = v.encode('utf-8')
        return struct.pack('<II', 4, len(b)) + b + b'\0' * ((4 - len(b) % 4) % 4)
    if isinstance(v, list):
        return struct.pack('<II', 28, len(v)) + b''.join(encode(x) for x in v)
    raise TypeError(type(v))


def send(sock, msg):
    payload = encode(msg)
    sock.sendall(struct.pack('<I', len(payload)) + payload)


def recv_exact(sock, n):
    buf = b''
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError('closed')
        buf += chunk
    return buf

# --- capture -----------------------------------------------------------------


def capture(args):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(('127.0.0.1', args.port))
    srv.listen(1)
    srv.settimeout(60)
    cmd = [args.godot, '--path', args.project, '--remote-debug', 'tcp://127.0.0.1:%d' % args.port,
           '--profiling', '--resolution', args.resolution]
    if args.fixed_fps:
        cmd += ['--fixed-fps', str(args.fixed_fps)]
    cmd += ['--script', args.script]
    log = open(args.out + '.log', 'w', encoding='utf-8')
    proc = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT)
    conn, _ = srv.accept()
    conn.settimeout(5)
    sigs = {}
    phases = {}
    order = []
    current = [None]
    totals = {}
    lines = []
    tid = [1]
    started = time.time()
    enabled = False

    def phase_bucket(name):
        if name not in phases:
            phases[name] = {'frames': 0, 'frame_ms': [], 'script_ms': [], 'functions': {}, 'worst': []}
            order.append(name)
        return phases[name]

    while True:
        if time.time() - started > args.timeout:
            print('timeout', file=sys.stderr)
            proc.kill()
            break
        try:
            size = struct.unpack('<I', recv_exact(conn, 4))[0]
            msg = Reader(recv_exact(conn, size)).variant()
        except socket.timeout:
            if proc.poll() is not None:
                break
            continue
        except ConnectionError:
            break
        if not isinstance(msg, list) or len(msg) != 3:
            continue
        name, thread, data = msg
        if not enabled:
            tid[0] = thread
            # profiler:servers [enable, [max functions per frame, native calls]]
            send(conn, ['profiler:servers', thread, [True, [args.max_functions, False]]])
            enabled = True
        if name == 'debug_enter':
            # a script error broke into the debugger: note it and go on
            lines.append('DEBUG_ENTER %s' % json.dumps(data, default=str)[:400])
            send(conn, ['continue', thread, []])
        elif name == 'output':
            for s in (data[0] if data and isinstance(data[0], list) else []):
                lines.append(s)
        elif name == 'bench:phase':
            ph, edge = data[0], data[1]
            current[0] = ph if edge == 'begin' else None
            if edge == 'begin':
                phase_bucket(ph)
        elif name == 'servers:function_signature':
            sigs[data[1]] = data[0]
        elif name in ('servers:profile_frame', 'servers:profile_total'):
            frame = data
            i = 6
            nservers = frame[i]
            i += 1
            for _ in range(nservers):
                i += 1
                i += 1 + frame[i]
            n = frame[i] // 5
            i += 1
            funcs = []
            for k in range(n):
                sig, calls, self_t, total_t, internal_t = frame[i + 5 * k:i + 5 * k + 5]
                funcs.append((sig, calls, self_t, total_t))
            if name == 'servers:profile_total':
                for sig, calls, self_t, total_t in funcs:
                    totals[sig] = {'calls': calls, 'self_ms': self_t * 1000.0, 'total_ms': total_t * 1000.0}
                continue
            if current[0] is None:
                continue
            b = phase_bucket(current[0])
            b['frames'] += 1
            b['frame_ms'].append(frame[1] * 1000.0)
            b['script_ms'].append(frame[5] * 1000.0)
            for sig, calls, self_t, total_t in funcs:
                f = b['functions'].setdefault(str(sig), [0, 0.0, 0.0])
                f[0] += calls
                f[1] += self_t * 1000.0
                f[2] += total_t * 1000.0
            # hitches: the worst frames of the phase with what filled them
            b['worst'].append((frame[1] * 1000.0, b['frames'], sorted(funcs, key=lambda x: -x[3])[:12]))
            b['worst'].sort(key=lambda w: -w[0])
            del b['worst'][5:]
    try:
        proc.wait(timeout=30)
    except subprocess.TimeoutExpired:
        proc.kill()
    log.close()
    out = {'meta': {'cmd': cmd, 'when': time.strftime('%Y-%m-%d %H:%M:%S')}, 'signatures': {str(k): v for k, v in sigs.items()},
           'phases': {}, 'order': order, 'totals': {sigs.get(k, str(k)): v for k, v in totals.items()}, 'output': lines}
    for name in order:
        b = phases[name]
        fr = max(1, b['frames'])
        funcs = {}
        for sig, (calls, self_ms, total_ms) in b['functions'].items():
            # keyed by file and function, not line: lines move between captures
            key = func_key(sigs.get(int(sig), sig))
            f = funcs.setdefault(key, {'calls_per_frame': 0.0, 'self_ms': 0.0, 'total_ms': 0.0})
            f['calls_per_frame'] += calls / fr
            f['self_ms'] += self_ms / fr
            f['total_ms'] += total_ms / fr
        worst = []
        for ms, at, fs in b['worst']:
            worst.append({'frame_ms': ms, 'frame': at, 'functions': [
                {'function': func_key(sigs.get(sig, sig)), 'calls': calls, 'self_ms': st * 1000.0, 'total_ms': tt * 1000.0}
                for sig, calls, st, tt in fs]})
        fms = sorted(b['frame_ms']) or [0.0]
        out['phases'][name] = {'frames': b['frames'], 'frame_ms_avg': sum(fms) / len(fms), 'frame_ms_p95': fms[int(len(fms) * 0.95)],
                               'script_ms_avg': sum(b['script_ms']) / max(1, len(b['script_ms'])), 'functions': funcs, 'worst': worst}
    with open(args.out, 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    for name in order:
        p = out['phases'][name]
        print('%-12s frames %4d  frame %.2f ms (p95 %.2f)  script %.2f ms' % (name, p['frames'], p['frame_ms_avg'], p['frame_ms_p95'], p['script_ms_avg']))
    print('wrote', args.out)

# --- reports -----------------------------------------------------------------


def func_key(sig):
    # res://path/file.gd::123::func -> res://path/file.gd::func
    parts = str(sig).split('::')
    if len(parts) >= 3:
        return '%s::%s' % (parts[0], parts[2])
    return str(sig)


def short(key):
    parts = key.split('::')
    if len(parts) >= 3:
        return '%s:%s %s' % (os.path.basename(parts[0]), parts[1], parts[2])
    if len(parts) == 2:
        return '%s %s' % (os.path.basename(parts[0]), parts[1])
    return key


def hotspots(args):
    cap = json.load(open(args.capture, encoding='utf-8'))
    for name in cap['order']:
        if args.phase and name != args.phase:
            continue
        p = cap['phases'][name]
        print('== %s: %d frames, frame %.2f ms (p95 %.2f), script %.2f ms' % (name, p['frames'], p['frame_ms_avg'], p['frame_ms_p95'], p['script_ms_avg']))
        rows = sorted(p['functions'].items(), key=lambda kv: -kv[1][args.by + '_ms'])
        print('   %8s %8s %8s  %s' % ('self ms', 'total ms', 'calls', 'function (per frame)'))
        for sig, f in rows[:args.top]:
            print('   %8.3f %8.3f %8.1f  %s' % (f['self_ms'], f['total_ms'], f['calls_per_frame'], short(sig)))


def hitches(args):
    cap = json.load(open(args.capture, encoding='utf-8'))
    for name in cap['order']:
        if args.phase and name != args.phase:
            continue
        print('== %s worst frames' % name)
        for w in cap['phases'][name].get('worst', []):
            print('  frame %d: %.1f ms' % (w['frame'], w['frame_ms']))
            for f in w['functions'][:args.top]:
                print('     %8.2f total %8.2f self %6d calls  %s' % (f['total_ms'], f['self_ms'], f['calls'], short(f['function'])))


def compare(args):
    a = json.load(open(args.before, encoding='utf-8'))
    b = json.load(open(args.after, encoding='utf-8'))
    for name in a['order']:
        if args.phase and name != args.phase:
            continue
        if name not in b['phases']:
            continue
        pa, pb = a['phases'][name], b['phases'][name]
        print('== %s: frame %.2f -> %.2f ms (p95 %.2f -> %.2f), script %.2f -> %.2f ms' % (
            name, pa['frame_ms_avg'], pb['frame_ms_avg'], pa['frame_ms_p95'], pb['frame_ms_p95'], pa['script_ms_avg'], pb['script_ms_avg']))
        keys = set(pa['functions']) | set(pb['functions'])
        rows = []
        for k in keys:
            x = pa['functions'].get(k, {}).get(args.by + '_ms', 0.0)
            y = pb['functions'].get(k, {}).get(args.by + '_ms', 0.0)
            rows.append((y - x, x, y, k))
        rows.sort(key=lambda r: -abs(r[0]))
        print('   %8s %8s %8s  %s' % ('before', 'after', 'change', 'function (%s ms per frame)' % args.by))
        for d, x, y, k in rows[:args.top]:
            print('   %8.3f %8.3f %+8.3f  %s' % (x, y, d, short(k)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    c = sub.add_parser('capture')
    c.add_argument('--project', required=True, help='isolated copy game/ folder')
    c.add_argument('--out', required=True)
    c.add_argument('--script', default='res://tests/bench_play.gd')
    c.add_argument('--resolution', default='1280x720')
    c.add_argument('--fixed-fps', type=int, default=0)
    c.add_argument('--godot', default='godot_console')
    c.add_argument('--port', type=int, default=6017)
    c.add_argument('--max-functions', type=int, default=400)
    c.add_argument('--timeout', type=float, default=900)
    h = sub.add_parser('hotspots')
    h.add_argument('capture')
    h.add_argument('--phase')
    h.add_argument('--top', type=int, default=20)
    h.add_argument('--by', choices=['self', 'total'], default='self')
    w = sub.add_parser('hitches')
    w.add_argument('capture')
    w.add_argument('--phase')
    w.add_argument('--top', type=int, default=8)
    k = sub.add_parser('compare')
    k.add_argument('before')
    k.add_argument('after')
    k.add_argument('--phase')
    k.add_argument('--top', type=int, default=20)
    k.add_argument('--by', choices=['self', 'total'], default='self')
    args = ap.parse_args()
    {'capture': capture, 'hotspots': hotspots, 'hitches': hitches, 'compare': compare}[args.cmd](args)


if __name__ == '__main__':
    main()
