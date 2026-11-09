#!/usr/bin/env python3
"""Merge scoped bindings into the CLIENT's VS Code keybindings.json (JSONC)."""
import argparse
import datetime
import json
from pathlib import Path
import re
import hashlib

BEGIN = '// BEGIN AstroNvim portable terminal keys'
END = '// END AstroNvim portable terminal keys'


def client_paths(path):
    path = path.absolute()
    # WSL installs client settings for the Windows account owning that path.
    match = re.match(r'^/mnt/([a-z])/Users/([^/]+)(/.*)$', str(path))
    if match:
        drive, user, tail = match.groups()
        return Path(f'/mnt/{drive}/Users/{user}'), f'{drive.upper()}:\\Users\\{user}' + tail.replace('/', '\\')
    return Path.home(), str(path)


def backup_directory(path):
    home, native = client_paths(path)
    ident = hashlib.sha256(native.lower().encode()).hexdigest()[:20]
    directory = home/'.astronvim/vscode-backups'/ident
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    return directory, native


def without_managed(text):
    if BEGIN not in text: return text
    start, stop = text.index(BEGIN), text.index(END) + len(END)
    before, after = text[:start], text[stop:]
    # Current and legacy installers put the separator before the managed block.
    clean_before, clean_after = significant(before).rstrip(), significant(after).lstrip()
    if clean_before.endswith(',') and clean_after.startswith(']'):
        at = len(clean_before)-1
        before = before[:at]+before[at+1:]
    elif clean_before.endswith(('[', ',')) and clean_after.startswith(','):
        at = len(after)-len(significant(after).lstrip())
        after = after[:at]+after[at+1:]
    result = before+after
    parse_jsonc(result)
    return result


def significant(text):
    # Keep offsets unchanged while masking JSONC comments. Strings (including
    # escaped quotes and URLs) must not be interpreted as comments.
    pattern = r'"(?:\\.|[^"\\])*"|//[^\r\n]*|/\*[\s\S]*?\*/'
    return re.sub(pattern, lambda m: m[0] if m[0].startswith('"') else
                  ''.join('\n' if c == '\n' else ' ' for c in m[0]), text)


def parse_jsonc(text):
    clean = significant(text)
    # Remove only commas outside strings that precede a closing bracket.
    clean = re.sub(r'"(?:\\.|[^"\\])*"|,(?=\s*[}\]])',
                   lambda m: m[0] if m[0].startswith('"') else ' ', clean)
    return json.loads(clean)


def install(path, bindings):
    existed = path.exists()
    raw = path.read_bytes() if existed else b'[]\n'
    text = raw.decode('utf-8-sig')
    if not isinstance(parse_jsonc(text), list):
        raise ValueError('keybindings.json 的根节点必须为数组；未修改原文件')
    entries = json.dumps(bindings, ensure_ascii=True, indent=2)[2:-2]
    block = BEGIN + '\n' + entries + '\n' + END
    if BEGIN in text or END in text:
        if text.count(BEGIN) != 1 or text.count(END) != 1:
            raise ValueError('重复或不完整的 AstroNvim 标记；未修改原文件')
        start, stop = text.index(BEGIN), text.index(END) + len(END)
        if start >= stop:
            raise ValueError('AstroNvim 标记顺序错误；未修改原文件')
        updated = text[:start] + block + text[stop:]
    else:
        clean = significant(text)
        closing = len(clean.rstrip()) - 1
        if clean[closing] != ']':
            raise ValueError('无法定位快捷键数组；未修改原文件')
        previous = clean[:closing].rstrip()[-1]
        comma = '' if previous in '[,' else ','
        updated = text[:closing] + comma + '\n' + block + '\n' + text[closing:]
    parse_jsonc(updated)
    encoded = (b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b'') + updated.encode('utf-8')
    directory, native = backup_directory(path)
    registration = directory/'registration.json'
    registration.write_text(json.dumps({'target':native}, ensure_ascii=False, indent=2)+'\n')
    if existed and raw == encoded:
        print('已是最新配置:', path)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now().strftime('%Y%m%d%H%M%S%f')
    backup = directory/f'keybindings-{stamp}.json'
    backup.write_bytes(raw)
    backup.chmod(0o600)
    print('备份:', backup)
    # Upgrading an earlier managed block must not make that old block the
    # baseline restored on exit. Keep its exact preimage as a separate backup.
    state_path = directory/'active.json'
    state = json.loads(state_path.read_text()) if state_path.exists() else None
    if state and state.get('installed_sha256') == hashlib.sha256(raw).hexdigest():
        baseline = (directory/state['backup']).read_bytes()
        baseline_exists = state['existed']
    else:
        baseline = without_managed(text).encode('utf-8') if BEGIN in text else raw
        baseline_exists = existed
    baseline_name = f'baseline-{stamp}.json'
    (directory/baseline_name).write_bytes(baseline)
    (directory/baseline_name).chmod(0o600)
    state_path.write_text(json.dumps({'target':native,'backup':baseline_name,'existed':baseline_exists,
        'installed_sha256':hashlib.sha256(encoded).hexdigest()},ensure_ascii=False,indent=2)+'\n')
    # Detect a concurrent editor save before replacing the configuration.
    if path.exists() != existed or (existed and path.read_bytes() != raw):
        raise RuntimeError('快捷键文件已被其他程序修改，请重试')
    path.write_bytes(encoded)
    print('已安装', len(bindings), '条终端全屏转发规则:', path)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('keybindings', type=Path, help='本机 VS Code 用户 keybindings.json 的实际路径')
    args = parser.parse_args()
    bindings = json.loads(Path(__file__).with_name('keybindings.json').read_text())
    install(args.keybindings.expanduser(), bindings)
