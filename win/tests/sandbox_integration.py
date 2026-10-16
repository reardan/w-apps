#!/usr/bin/env python3
"""Linux ABI8 offline confinement and real local GL presentation; no HTTP parity claim."""
import ctypes
from collections import Counter
import fcntl
import json
import os
from pathlib import Path
import select
import socket
import struct
import subprocess
import sys
import tempfile
import time

WIN = str(Path(sys.argv[1]).resolve())
ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'win/bin' / os.environ.get('WIN_SANDBOX_TEST_OUTPUT', 'offline-sandbox')
OUTPUT.mkdir(parents=True, exist_ok=True)
libc = ctypes.CDLL(None, use_errno=True)


class Filter(ctypes.Structure):
    _fields_ = [('code', ctypes.c_ushort), ('jt', ctypes.c_ubyte),
                ('jf', ctypes.c_ubyte), ('k', ctypes.c_uint)]


class Program(ctypes.Structure):
    _fields_ = [('length', ctypes.c_ushort), ('filters', ctypes.POINTER(Filter))]


def deny_landlock():
    """Simulate an unsupported/disabled kernel; the requested app must not run."""
    filters = (Filter * 4)(Filter(0x20, 0, 0, 0), Filter(0x15, 0, 1, 444),
                           Filter(0x06, 0, 0, 0x50001), Filter(0x06, 0, 0, 0x7fff0000))
    program = Program(4, filters)
    if libc.prctl(38, 1, 0, 0, 0) != 0 or libc.syscall(317, 1, 0, ctypes.byref(program)) != 0:
        os._exit(99)


rejected = subprocess.run([WIN, '--isolated-interactive', '--sandbox-root', '/tmp',
                           '--page', '/tmp/never-read.html'], preexec_fn=deny_landlock,
                          capture_output=True, timeout=5)
assert rejected.returncode == 1 and b'Landlock ABI 8' in rejected.stderr, rejected
abi = libc.syscall(444, 0, 0, 1)
if abi < 8:
    print('SKIP live sandbox/GL tests: Landlock ABI8 unavailable; fail-closed startup passed')
    raise SystemExit(0)
if not os.environ.get('DISPLAY'):
    raise SystemExit(subprocess.call(['xvfb-run', '-a', sys.executable, __file__, WIN]))


def receive(sock, count):
    result = bytearray()
    while len(result) < count:
        part = sock.recv(count - len(result))
        assert part, ('truncated worker response', count, len(result))
        result += part
    return bytes(result)


def response(sock, sequence, frame_sequence):
    magic, length, actual, kind, revision = struct.unpack('<8siiii', receive(sock, 24))
    assert (magic, actual) == (b'WINT0001', sequence)
    assert (kind, revision) in ((101, 0), (102, 2))
    payload = receive(sock, length)
    scripts, resources, count, node = struct.unpack('<4i', payload[:16])
    assert (scripts, resources, count) == (0, 0, 1), payload
    if kind == 102:
        metadata = struct.unpack('<9i', payload[16:52])
        assert metadata[0] == 11
        if sequence == 1:
            assert metadata[7:9] == (320, 240), metadata
    header = struct.unpack('<4s11i', receive(sock, 48))
    assert header[:10] == (b'WFRM', 1, 1, 11, frame_sequence, 1, 32, 32, 128, 4096), header
    pixels = receive(sock, 4096)
    assert pixels == b'\x00\x00\xff\xff' * (32 * 32), Counter(pixels[i:i+4] for i in range(0, len(pixels), 4))
    assert node > 0
    return node


def acknowledgement(sock, generation, sequence):
    sock.sendall(struct.pack('<4s11i', b'WFRM', 1, 2, generation, sequence,
                             0, 0, 0, 0, 0, 0, 0))


def run(arguments, **options):
    return subprocess.run([WIN, *arguments], capture_output=True, timeout=30, **options)


with tempfile.TemporaryDirectory(prefix='win-offline-sandbox-') as temporary:
    base = Path(temporary)
    content = base / 'content'
    content.mkdir()
    outside = base / 'outside.css'
    outside.write_text('/* OUTSIDE_SECRET_MARKER */ body { background: rgb(255,0,255); }')
    (content / 'escape.css').symlink_to(outside)
    inside = content / 'inside.css'
    inside.write_text('/* INSIDE_ALLOWED_MARKER */ html,body { margin:0; background:rgb(0,255,0); } canvas { width:128px; height:128px; }')
    page = content / 'canvas.html'
    # Compile and link shaders after confinement, then draw a full-cover triangle.
    # This exercises driver work beyond clearing a pre-created framebuffer.
    page.write_text('''<title>Offline sandbox pixels</title><link rel="stylesheet" href="inside.css">
<canvas id="c" width="32" height="32"></canvas><script>
var gl=document.getElementById('c').getContext('webgl2');
var vs=gl.createShader(gl.VERTEX_SHADER);
gl.shaderSource(vs,'#version 300 es\\nprecision highp float;in vec2 position;void main(){gl_Position=vec4(position,0.,1.);}');
gl.compileShader(vs);if(!gl.getShaderParameter(vs,gl.COMPILE_STATUS))throw gl.getShaderInfoLog(vs);
var fs=gl.createShader(gl.FRAGMENT_SHADER);
gl.shaderSource(fs,'#version 300 es\\nprecision highp float;out vec4 pixel;void main(){pixel=vec4(0.,0.,1.,1.);}');
gl.compileShader(fs);if(!gl.getShaderParameter(fs,gl.COMPILE_STATUS))throw gl.getShaderInfoLog(fs);
var program=gl.createProgram();gl.attachShader(program,vs);gl.attachShader(program,fs);gl.linkProgram(program);
if(!gl.getProgramParameter(program,gl.LINK_STATUS))throw gl.getProgramInfoLog(program);
gl.useProgram(program);var buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buffer);
gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,3,-1,-1,3]),gl.STATIC_DRAW);
var attr=gl.getAttribLocation(program,'position');gl.enableVertexAttribArray(attr);
gl.vertexAttribPointer(attr,2,gl.FLOAT,false,0,0);gl.drawArrays(gl.TRIANGLES,0,3);
if(gl.getError()!==0)throw 'sandbox draw error';
</script>''')
    profile = ['--sandbox-root', str(content)]
    for arguments in ([*profile, '--dump', '--page', str(page)],
                      [*profile, '--isolated-dump', '--page', str(page)],
                      [*profile, '--isolated-dump', '--isolated-interactive', '--page', str(page)],
                      [*profile, '--script-worker', '--isolated-interactive', '--worker-limit', '4096', '--page', str(page)],
                      ['--sandbox-root', '/', '--isolated-interactive'],
                      ['--sandbox-root', 'relative', '--isolated-interactive'],
                      ['--sandbox-root', '--isolated-interactive'],
                      [*profile, '--isolated-interactive', '--page', 'http://127.0.0.1:1/']):
        result = run(arguments)
        assert result.returncode != 0, (arguments, result)
    result = run([*profile, '--resource', str(inside), '--kind', 'stylesheet'])
    assert result.returncode == 0 and b'INSIDE_ALLOWED_MARKER' in result.stdout, result
    for address in (outside, content / 'escape.css', content / '../outside.css', Path('/proc/self/environ')):
        result = run([*profile, '--resource', str(address), '--kind', 'stylesheet'])
        assert result.returncode != 0 and b'OUTSIDE_SECRET_MARKER' not in result.stdout, result
    missing = run(['--sandbox-root', str(base / 'missing'), '--resource', str(inside), '--kind', 'stylesheet'])
    assert missing.returncode == 1 and b'Cannot enforce' in missing.stderr, missing

    descriptor = os.open(outside, os.O_RDONLY)
    high = fcntl.fcntl(descriptor, fcntl.F_DUPFD, 2048)
    os.close(descriptor)
    for mode in ('normal', 'stale', 'crash', 'partial'):
        parent, child = socket.socketpair()
        parent.settimeout(10)
        process = subprocess.Popen([WIN, '--interactive-worker', *profile, '--page', str(page),
            '--worker-limit', '8388608', '--worker-generation', '11'], stdin=child,
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, pass_fds=(high,),
            env=dict(os.environ, WIN_SCRIPT_WORKER_PARENT=str(os.getpid())))
        child.close()
        try:
            response(parent, 0, 1)
            descriptors = [os.readlink(p) for p in Path(f'/proc/{process.pid}/fd').iterdir()]
            (OUTPUT / 'worker-fds.json').write_text(json.dumps(descriptors, indent=2) + '\n')
            assert str(outside) not in descriptors, descriptors
            threads = list(Path(f'/proc/{process.pid}/task').iterdir())
            for thread in threads:
                status = (thread / 'status').read_text()
                assert 'NoNewPrivs:\t1' in status and 'Seccomp:\t2' in status, status
            # ACK backpressure still applies inside the OS confinement domain.
            assert not select.select([parent], [], [], .05)[0]
            if mode == 'crash':
                process.kill()
                assert process.wait(timeout=5) == -9
                continue
            acknowledgement(parent, 10 if mode == 'stale' else 11, 1)
            if mode != 'stale':
                parent.sendall(struct.pack('<8s7i', b'WINT0001', 12, 1, 1, 1, 0, 320, 240))
                if mode == 'partial':
                    receive(parent, 29)
                    parent.close()
                    process.kill()
                    assert process.wait(timeout=5) == -9
                    continue
                response(parent, 1, 2)
                acknowledgement(parent, 11, 2)
            parent.close()
            assert process.wait(timeout=5) == 0, process.stderr.read()
        finally:
            parent.close()
            if process.poll() is None:
                process.kill()
            process.wait(timeout=5)
            process.stderr.close()
    os.close(high)

    # The display-only parent re-fetches linked CSS. Test that its helpers also
    # receive the profile: an outside stylesheet would turn the page magenta.
    listener = socket.socket()
    listener.bind(('127.0.0.1', 0))
    listener.listen()
    blocked_page = content / 'blocked.html'
    blocked_page.write_text(page.read_text().replace('<canvas',
        f'<link rel="stylesheet" href="escape.css"><link rel="stylesheet" href="http://127.0.0.1:{listener.getsockname()[1]}/blocked.css"><canvas', 1))
    shot = OUTPUT / 'local-gl.ppm'
    report_path = OUTPUT / 'local-gl.json'
    environment = dict(os.environ, WIN_SANDBOX_SECRET='do-not-forward', AWS_SECRET_ACCESS_KEY='do-not-forward')
    process = subprocess.Popen([WIN, '--isolated-interactive', *profile, '--page', str(blocked_page),
        '--frames', '240', '--screenshot', str(shot), '--report', str(report_path)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment)
    sanitized = False
    deadline = time.monotonic() + 5
    while process.poll() is None and time.monotonic() < deadline and not sanitized:
        children = Path(f'/proc/{process.pid}/task/{process.pid}/children').read_text().split()
        for child in children:
            try:
                command = Path(f'/proc/{child}/cmdline').read_bytes()
                if b'--interactive-worker' in command:
                    entries = Path(f'/proc/{child}/environ').read_bytes().split(b'\0')
                    assert not any(b'do-not-forward' in entry for entry in entries), entries
                    sanitized = True
            except FileNotFoundError:
                pass
        time.sleep(.01)
    stdout, stderr = process.communicate(timeout=30)
    assert process.returncode == 0 and sanitized, (stdout, stderr, sanitized)
    assert not select.select([listener], [], [], .05)[0], 'Offline resource contacted a TCP server'
    listener.close()
    report = json.loads(report_path.read_text())
    assert report['title'] == 'Offline sandbox pixels' and report['script_failures'] == 0, report
    assert report['resource_failures'] >= 2, report
    magic, dimensions, maximum, pixels = shot.read_bytes().split(b'\n', 3)
    assert magic == b'P6' and maximum == b'255'
    colors = [pixels[i:i+3] for i in range(0, len(pixels), 3)]
    blue = colors.count(b'\x00\x00\xff')
    green = colors.count(b'\x00\xff\x00')
    assert blue >= 16000 and green >= 100000, (blue, green, report)
    evidence = dict(report, landlock_abi=abi, blue_pixels=blue, green_pixels=green,
                    environment_sanitized=sanitized, high_inherited_fd_closed=True,
                    policy_threads=len(threads), fail_closed_unavailable_kernel=True,
                    crash_reaped=True, partial_response_cancelled=True,
                    network_contact=False, profile='offline local GL; HTTP M1–M3 unclaimed')
    (OUTPUT / 'evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps(evidence))
print('Offline sandbox: real GL shaders/paint, TSYNC threads, resources, environment, FDs, ACK/resize/teardown: OK')
