"""Actual generated Marea UI with isolated logic on a disposable CI desktop.

No system input, device services, account, network or model call is exercised.
The screenshots and scene commands cover rendering/layout and named interaction,
not hardware or installed-product acceptance. Never run this on a user's desktop.
"""
from pathlib import Path
import argparse
import ctypes as C
from ctypes import wintypes as W
import hashlib
import json
import os
import re
import struct
import subprocess
import sys
import time
import zlib


def require_ci():
    if (sys.platform != 'win32' or os.environ.get('GITHUB_ACTIONS') != 'true'
            or os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted'
            or os.environ.get('MAREA_CI_PROFILE_UI') != '1'):
        raise RuntimeError('Visible fixture requires the explicit step on a disposable GitHub-hosted Windows runner')


def fixture_source(root):
    source = (root / 'marea-desktop.plm').read_text(encoding='utf-8')
    for folder in ('common', 'lang', 'shaders', 'assets', 'wardrobe'):
        source = source.replace('"' + folder + '/', '"' + (root / folder).as_posix() + '/')
    source = re.sub(r'keyboard: on_demand[^\n]*', 'keyboard: none', source)
    source = source.replace('reserve: 72 while taking_room', 'reserve: 0')
    source, count = re.subn(r'permissions\s*\{[^{}]*\}', 'permissions { }', source)
    assert count == 1, 'The fixture must deny every external service'
    assert source.count('scene Marea {') == 1
    source = source.replace('scene Marea {', 'scene MareaProfileCI {\n'
        ' event fixture_stage ->\n fact fixture_ready = false\n fact fixture_volume_calls = 0\n', 1)
    return source


class Desktop:
    def __init__(self):
        self.user = C.WinDLL('user32', use_last_error=True)
        self.gdi = C.WinDLL('gdi32', use_last_error=True)
        self.callback = C.WINFUNCTYPE(W.BOOL, W.HWND, W.LPARAM)
        for lib, name, result, args in [
            (self.user, 'EnumWindows', W.BOOL, [self.callback, W.LPARAM]),
            (self.user, 'GetWindowThreadProcessId', W.DWORD, [W.HWND, C.POINTER(W.DWORD)]),
            (self.user, 'GetWindowTextW', C.c_int, [W.HWND, W.LPWSTR, C.c_int]),
            (self.user, 'IsWindowVisible', W.BOOL, [W.HWND]),
            (self.user, 'SetProcessDpiAwarenessContext', W.BOOL, [W.HANDLE]),
            (self.user, 'GetClientRect', W.BOOL, [W.HWND, C.POINTER(W.RECT)]),
            (self.user, 'ClientToScreen', W.BOOL, [W.HWND, C.POINTER(W.POINT)]),
            (self.user, 'GetDC', W.HDC, [W.HWND]),
            (self.user, 'ReleaseDC', C.c_int, [W.HWND, W.HDC]),
            (self.user, 'PostMessageW', W.BOOL, [W.HWND, W.UINT, W.WPARAM, W.LPARAM]),
            (self.gdi, 'CreateCompatibleDC', W.HDC, [W.HDC]),
            (self.gdi, 'CreateCompatibleBitmap', W.HBITMAP, [W.HDC, C.c_int, C.c_int]),
            (self.gdi, 'SelectObject', W.HANDLE, [W.HDC, W.HANDLE]),
            (self.gdi, 'BitBlt', W.BOOL, [W.HDC, C.c_int, C.c_int, C.c_int, C.c_int, W.HDC, C.c_int, C.c_int, W.DWORD]),
            (self.gdi, 'GetDIBits', C.c_int, [W.HDC, W.HBITMAP, W.UINT, W.UINT, C.c_void_p, C.c_void_p, W.UINT]),
            (self.gdi, 'DeleteObject', W.BOOL, [W.HANDLE]),
            (self.gdi, 'DeleteDC', W.BOOL, [W.HDC]),
        ]:
            function = getattr(lib, name)
            function.restype, function.argtypes = result, args
        if not self.user.SetProcessDpiAwarenessContext(W.HANDLE(-4)):
            raise C.WinError(C.get_last_error())

    def pid(self, hwnd):
        pid = W.DWORD()
        assert self.user.GetWindowThreadProcessId(hwnd, C.byref(pid))
        return pid.value

    def window(self, pid, title):
        found = []

        @self.callback
        def visit(hwnd, _):
            text = C.create_unicode_buffer(256)
            self.user.GetWindowTextW(hwnd, text, len(text))
            if text.value.startswith(title) and self.pid(hwnd) == pid and self.user.IsWindowVisible(hwnd):
                found.append(hwnd)
            return True

        assert self.user.EnumWindows(visit, 0)
        assert len(found) <= 1
        return found[0] if found else None

    def pixels(self, hwnd):
        rect, point = W.RECT(), W.POINT()
        assert self.user.GetClientRect(hwnd, C.byref(rect))
        assert self.user.ClientToScreen(hwnd, C.byref(point))
        width, height = rect.right, rect.bottom
        assert 100 <= width <= 4096 and 100 <= height <= 2160
        source = self.user.GetDC(None)
        target = self.gdi.CreateCompatibleDC(source)
        bitmap = self.gdi.CreateCompatibleBitmap(source, width, height)
        assert source and target and bitmap
        old = self.gdi.SelectObject(target, bitmap)
        try:
            assert self.gdi.BitBlt(target, 0, 0, width, height, source, point.x, point.y, 0x00CC0020)
            self.gdi.SelectObject(target, old)
            old = None
            header = C.create_string_buffer(struct.pack('<IiiHHIIiiII', 40, width, -height, 1, 32, 0, 0, 0, 0, 0, 0))
            pixels = C.create_string_buffer(width * height * 4)
            assert self.gdi.GetDIBits(target, bitmap, 0, height, pixels, header, 0) == height
            return width, height, pixels.raw
        finally:
            if old:
                self.gdi.SelectObject(target, old)
            self.gdi.DeleteObject(bitmap)
            self.gdi.DeleteDC(target)
            self.user.ReleaseDC(None, source)


def png(path, picture):
    width, height, bgra = picture
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        row = bgra[y * width * 4:(y + 1) * width * 4]
        for i in range(0, len(row), 4):
            rows.extend((row[i + 2], row[i + 1], row[i]))

    def chunk(name, data):
        return struct.pack('>I', len(data)) + name + data + struct.pack('>I', zlib.crc32(name + data))

    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
                     + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


FIXTURE_LOGIC = r'''
fact.locale="es"
fact.hidden=false;fact.needed=true;fact.home=0
fact["hosts.0"]=true;fact["hosts.1"]=false
fact["sound.volume"]=0.42;fact["sound.input"]=0.3;fact["display.level"]=0.55;fact["display.present"]=true
fact.windows_wifi_present=true;fact.windows_bluetooth_present=true
fact.windows_key_available=true;fact.windows_key_enabled=true;fact.windows_key_busy=false
fact["wifi.state"]=1;fact["bt.on"]=true
for k=0,2 do fact["windows_level_available."..k]=true end
on("set_volume",function(v)
    fact.fixture_volume_calls+=1
    fact["sound.volume"]=v
    fact["windows_level_pending.1"]=false
end)
on("fixture_stage",function(stage)
    fact.chatting=false;fact.open=false;fact.menu_open=false
    fact["chat.signed_in"]=false;fact["chat.signing"]=false
    fact["chat.state"]="offline";fact["chat.live"]=-1
    model["chat.rows"]={}
    text["chat.input"]=""
    if stage==6 then
        fact.open=true;fact.page="none"
    elseif stage==7 then
        fact.open=true;fact.page="settings";fact.section="windows_shortcuts"
    elseif stage==0 then
        fact.chatting=true
    elseif stage==1 then
        fact.chatting=true;fact["chat.signing"]=true
        text["chat.login_hint"]="Código de ejemplo: ABCD-EFGH. No es una sesión real."
    elseif stage==2 then
        fact.open=true;fact.page="settings";fact.section="talk"
    elseif stage==3 then
        fact.chatting=true;fact["chat.signed_in"]=true;fact["chat.state"]="awaiting"
        model["chat.rows"]={
            {kind=1,text="Prueba de diseño: ¿puedes escribir España, café y 日本語?",detail="",state=1},
            {kind=2,text="Estos son datos de prueba para revisar las letras, las burbujas y el desplazamiento. No se ha contactado con ningún modelo ni se ha ejecutado ninguna acción.",detail="",state=1},
            {kind=4,text="Acción de ejemplo: escribir «España, café y 日本語» en una ventana de prueba.",detail="Escribir en la aplicación de prueba",state=0},
        }
    elseif stage==4 then
        fact.open=true;fact.page="settings";fact.section="menu"
    elseif stage==5 then
        fact.chatting=true;fact["chat.signed_in"]=true;fact["chat.state"]="idle"
        local rows={}
        for i=1,12 do rows[i]={kind=if i%2==0 then 2 else 1,text="Mensaje de ejemplo "..i..": España, café y 日本語. Un párrafo con texto suficiente para comprobar que la altura se mide y la conversación se desplaza sin superponer las líneas.",detail="",state=1} end
        model["chat.rows"]=rows
    end
end)
fact.fixture_ready=true
'''


def nodes(parts):
    for node in parts:
        yield node
        yield from nodes(node.get('nodes', node.get('children', [])))


def exercise(binary, output, root):
    desktop = Desktop()
    scene = output / 'Marea profile ñ 海.plm'
    scene.write_text(fixture_source(root), encoding='utf-8')
    scene.with_suffix('.luau').write_text(FIXTURE_LOGIC, encoding='utf-8')
    env = dict(os.environ, APPDATA=str(output / 'state'), LOCALAPPDATA=str(output / 'local'),
               PLEAMAR_CONFIG=str(output / 'config'), PLEAMAR_SOCKET_DIR=f'marea-profile-ci-{os.getpid()}',
               MAREA_SEARCH_HOTKEY='', PLEAMAR_NO_RELAUNCH='1')
    flags = subprocess.CREATE_NO_WINDOW | subprocess.BELOW_NORMAL_PRIORITY_CLASS
    report = dict(passed=False, fixture_logic=True, environment='github-hosted', physical_input=False,
                  device_services=False, real_account=False, full_product_acceptance=False,
                  binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
                  scene_sha256=hashlib.sha256(scene.read_bytes()).hexdigest(), checks=[], images=[])
    process, hwnd = None, None

    def run(arguments):
        result = subprocess.run([str(binary), *arguments], env=env, capture_output=True,
                                encoding='utf-8', errors='replace', timeout=15, creationflags=flags)
        with (output / 'commands.log').open('a', encoding='utf-8') as trace:
            trace.write(json.dumps(arguments, ensure_ascii=False) + '\n' + result.stdout + result.stderr)
        if result.returncode or result.stdout.lstrip().startswith('?'):
            raise RuntimeError(result.stdout + result.stderr)
        return result.stdout.strip()

    def ask(command):
        return run(['--say', scene.stem, command])

    def until(predicate, label):
        deadline, last = time.monotonic() + 40, None
        while time.monotonic() < deadline:
            if process and process.poll() is not None:
                raise RuntimeError('Scene stopped during ' + label)
            try:
                value = predicate()
                if value:
                    return value
            except (OSError, RuntimeError) as error:
                last = error
            time.sleep(.15)
        raise TimeoutError(f'{label}: {last}')

    def tree(label):
        value = json.loads(ask('describe json'))
        (output / (label + '.json')).write_text(json.dumps(value, indent=2, ensure_ascii=False), encoding='utf-8')
        return list(nodes(value))

    def capture(label):
        picture = desktop.pixels(hwnd)
        # Reject a blank/flat surface, but retain pixels for actual visual review.
        assert len(set(picture[2][i:i + 3] for i in range(0, len(picture[2]), 16))) > 100
        path = output / (label + '.png')
        png(path, picture)
        report['images'].append(dict(file=path.name, width=picture[0], height=picture[1],
                                     sha256=hashlib.sha256(path.read_bytes()).hexdigest()))

    try:
        run(['--check', str(scene)])
        with (output / 'scene.log').open('w', encoding='utf-8') as log:
            process = subprocess.Popen([str(binary), '--scene', str(scene), '--no-hud'], env=env,
                                       stdout=log, stderr=log, creationflags=flags)
            until(lambda: ask('get fixture_ready') == 'true', 'fixture initialization')
            hwnd = until(lambda: desktop.window(process.pid, 'pleamar surface 0 · '), 'main scene window')
            ask('emit fixture_stage 6')
            until(lambda: any(n.get('label') == 'Volumen' for n in tree('controls-tree')), 'control center')
            time.sleep(1.2)
            visible = tree('controls-tree')
            volume = next(n for n in visible if n.get('label') == 'Volumen' and n.get('role') == 'slider')
            assert volume.get('value') == '42%', volume
            assert any(n.get('checked') is True and n.get('role') == 'toggle' for n in visible)
            assert any(n.get('label') == 'Cerrar' for n in visible)
            capture('01-controls')
            response = ask(f'drag {volume["name"]} 0 -30')
            assert 'dragged' in response, response
            assert float(ask('get fixture_volume_calls')) > 0
            assert abs(float(ask('get sound.volume')) - .42) > .05
            capture('02-volume')
            report['checks'].append('Spanish slider value/labels and named drag reaching isolated Luau')
            ask('emit fixture_stage 7')
            until(lambda: any(n.get('label') == 'Usar la tecla Windows para Marea'
                              for n in tree('shortcuts-tree')), 'shortcut page')
            key = next(n for n in tree('shortcuts-tree') if n.get('label') == 'Usar la tecla Windows para Marea')
            assert key['role'] == 'toggle' and key['checked'] is True, key
            time.sleep(1.2)
            capture('03-shortcuts')
            report['checks'].append('Translated checked Windows-key setting; no hook enabled')
            labels = ('signed-out', 'login-code', 'account-settings', 'approval-card', 'settings-menu', 'long-conversation')
            report['layout_state'] = {}
            for stage, label in enumerate(labels):
                ask(f'emit fixture_stage {stage}')
                time.sleep(1.5)
                state = {name: ask('get ' + name) for name in ('chat.rows.count', 'chat.length', 'chat.from_end', 'chat.stuck')}
                report['layout_state'][label] = state
                tree(label + '-tree')
                capture(f'{stage + 4:02}-{label}')
                if label == 'long-conversation':
                    assert state['chat.rows.count'] == '12', state
                    assert state['chat.stuck'] == 'true', state
                    assert float(state['chat.length']) > 404, state
                    assert abs(float(state['chat.from_end']) - 404) < 1, state
            report['checks'].append('Six native chat/settings states and long conversation keeps the visible tail')
            assert desktop.user.PostMessageW(hwnd, 0x10, 0, 0)
            assert process.wait(timeout=20) == 0
        logs = (output / 'scene.log').read_text(encoding='utf-8')
        assert 'first frame' in logs and 'runtime error:' not in logs, logs
        report['passed'] = True
    finally:
        if process and process.poll() is None:
            if hwnd:
                desktop.user.PostMessageW(hwnd, 0x10, 0, 0)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=10)
        (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    require_ci()
    output = args.output.resolve()
    temporary = Path(os.environ['RUNNER_TEMP']).resolve()
    assert output != temporary and output.is_relative_to(temporary), 'Evidence must be in a new runner-temp directory'
    output.mkdir(parents=True, exist_ok=False)
    exercise(args.binary.resolve(strict=True), output, Path(__file__).resolve().parents[1])


if __name__ == '__main__':
    main()
