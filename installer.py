#!/usr/bin/env python3
"""Reconstruct the portable installation from locked upstream inputs and our patches.

Only bootstrap tools come from the host. Never run sudo, edit profiles, or update
dependencies implicitly. Build/download state stays below the selected prefix.
"""
import argparse
import concurrent.futures
import contextlib
import fcntl
import gzip
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.request
import zipfile

HERE = Path(__file__).resolve().parent
ARCHES = ('x86_64', 'aarch64')


class InstallError(RuntimeError):
    pass


class Unavailable(InstallError):
    pass


class Incompatible(InstallError):
    pass


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.new')
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    temporary.replace(path)


def inside(path, root):
    try:
        Path(path).resolve().relative_to(Path(root).resolve())
        return True
    except ValueError:
        return False


def extract(archive, target):
    """Extract verified archives without accepting path escapes or device nodes."""
    target = Path(target)
    target.mkdir(parents=True, exist_ok=True)
    def destination(name):
        if Path(name).is_absolute() or '..' in Path(name).parts:
            raise InstallError('Unsafe archive member: ' + name)
        path = target / name
        if not inside(path, target):
            raise InstallError('Archive link escapes destination: ' + name)
        return path
    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as z:
            for info in z.infolist():
                path = destination(info.filename)
                mode = info.external_attr >> 16
                if info.is_dir():
                    path.mkdir(parents=True, exist_ok=True)
                    continue
                path.parent.mkdir(parents=True, exist_ok=True)
                if stat.S_ISLNK(mode):
                    link = z.read(info).decode()
                    if Path(link).is_absolute() or not inside(path.parent / link, target):
                        raise InstallError('Unsafe zip link: ' + info.filename)
                    path.symlink_to(link)
                else:
                    with z.open(info) as source, path.open('wb') as out:
                        shutil.copyfileobj(source, out)
                    path.chmod((mode & 0o777) or 0o644)
        return
    with tarfile.open(archive, 'r:*') as tar:
        hardlinks = []
        for member in tar:
            path = destination(member.name)
            if member.isdir():
                path.mkdir(parents=True, exist_ok=True)
            elif member.issym():
                if Path(member.linkname).is_absolute() or not inside(path.parent / member.linkname, target):
                    raise InstallError('Unsafe tar link: ' + member.name)
                path.parent.mkdir(parents=True, exist_ok=True)
                if path.is_symlink():
                    path.unlink()
                path.symlink_to(member.linkname)
            elif member.islnk():
                hardlinks.append((path, destination(member.linkname)))
            elif member.isfile():
                path.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member) as source, path.open('wb') as out:
                    shutil.copyfileobj(source, out)
                path.chmod(member.mode & 0o777)
                os.utime(path, (member.mtime, member.mtime))
            else:
                raise InstallError('Unsupported archive member: ' + member.name)
        for path, source in hardlinks:
            if not inside(source, target) or not source.is_file():
                raise InstallError('Unsafe hard link: ' + str(path))
            path.parent.mkdir(parents=True, exist_ok=True)
            os.link(source, path)


def lockfile():
    lock = json.loads((HERE / 'dependencies.lock.json').read_text(encoding='utf-8'))
    if lock.get('schema') != 1:
        raise InstallError('Unsupported dependency lock schema')
    for name, item in lock['components'].items():
        if not item.get('version') or 'latest' in item['version'].lower():
            raise InstallError('Unpinned version: ' + name)
        for value in [item.get('source'), *item.get('binaries', {}).values()]:
            if value is None:
                continue
            if not value['url'].startswith('https://') or 'latest' in value['url']:
                raise InstallError('Unpinned URL: ' + name)
            if not re.fullmatch('[0-9a-f]{64}', value['sha256']):
                raise InstallError('Missing SHA256: ' + name)
    for file in ('plugins.lock.json', 'parsers.lock.json'):
        for item in json.loads((HERE / file).read_text()):
            if not re.fullmatch('[0-9a-f]{40}', item['commit']):
                raise InstallError('Missing exact Git commit: ' + item['name'])
    manifest = HERE / 'source-files.json'
    if manifest.exists():
        for name, expected in json.loads(manifest.read_text()).items():
            if not inside(HERE / name, HERE) or digest(HERE / name) != expected:
                raise InstallError('Source package checksum mismatch: ' + name)
    return lock


class Installer:
    def __init__(self, args, lock):
        self.args, self.lock = args, lock
        self.arch = args.architecture or platform.machine()
        self.root = Path(args.prefix).expanduser().resolve()
        self.work = self.root / '.installer'
        self.cache = Path(args.cache).expanduser().resolve() if args.cache else self.work / 'downloads'
        self.jobs = args.jobs
        self.forced = set(filter(None, args.from_source.split(',')))
        unknown = self.forced - set(lock['components'])
        if unknown:
            raise InstallError('Unknown --from-source component: ' + ', '.join(sorted(unknown)))
        unsupported = [n for n in self.forced if 'source' not in lock['components'][n]]
        if unsupported:
            raise InstallError('Pinned bootstrap binaries have no source recipe: ' + ', '.join(unsupported))
        self.hostenv = os.environ.copy()
        self.env = self.hostenv.copy()
        # Do not inherit another AstroNvim, Python, Rust or Oracle installation.
        for name in ('LD_LIBRARY_PATH', 'PYTHONHOME', 'PYTHONPATH', 'VIMRUNTIME', 'RUSTUP_TOOLCHAIN',
                     'RUSTC_WRAPPER', 'RUSTFLAGS', 'CARGO_ENCODED_RUSTFLAGS', 'CARGO_TARGET_DIR',
                     'GIT_EXEC_PATH', 'GIT_TEMPLATE_DIR', 'GIT_SSL_CAINFO', 'CURL_CA_BUNDLE',
                     'CFLAGS', 'CXXFLAGS', 'CPPFLAGS', 'LDFLAGS', 'PKG_CONFIG_PATH', 'CONFIG_SITE',
                     'CC','CXX','AR','LD','RANLIB','PKG_CONFIG','CMAKE_TOOLCHAIN_FILE','CMAKE_PREFIX_PATH',
                     'PKG_CONFIG_LIBDIR','PKG_CONFIG_SYSROOT_DIR','RUSTC','RUSTDOC','CARGO_BUILD_TARGET',
                     'DESTDIR','PREFIX','LIBRARY_PATH','CPATH','C_INCLUDE_PATH','CPLUS_INCLUDE_PATH',
                     'MAKEFLAGS','MFLAGS','BASH_ENV','ENV'):
            self.env.pop(name, None)
        self.env.update({
            'PATH': '/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin',
            'LC_ALL': 'C', 'CFLAGS': '-O2 -g0 -fPIC', 'CXXFLAGS': '-O2 -g0 -fPIC',
            'CPPFLAGS': '-I' + str(self.root / 'opt/include'),
            'LDFLAGS': '-L' + str(self.root / 'opt/lib'),
            'LD_LIBRARY_PATH': str(self.root / 'opt/lib') + ':' + str(self.root / 'opt/python/lib'),
            'PKG_CONFIG_PATH': str(self.root / 'opt/lib/pkgconfig'),
            'CMAKE_PREFIX_PATH': str(self.root / 'opt'),
            'CARGO_HOME': str(self.work / 'cargo'),
            'CARGO_BUILD_JOBS': str(self.jobs),
            'CARGO_NET_RETRY': '2',
            'npm_config_cache': str(self.work / 'npm'),
            'TMPDIR': str(self.work / 'tmp'),
            'PYTHONDONTWRITEBYTECODE': '1',
            'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null',
        })
        self.state = {'lock_sha256': digest(HERE / 'dependencies.lock.json'), 'architecture': self.arch, 'steps': {}}
        self.counter = 0
        self.run_id = time.strftime('%Y%m%d-%H%M%S') + '-' + str(os.getpid())
        self.active_step = ''
        self.prepared = False

    def prepare(self):
        if platform.system() != 'Linux' or self.arch not in ARCHES or self.arch != platform.machine():
            raise InstallError('Native Linux x86_64 or aarch64 required; cross-compile is not supported')
        if self.root == Path('/') or self.root == Path.home() or inside(HERE, self.root):
            raise InstallError('Choose a separate installation directory, not /, home or this source directory')
        if self.root.exists() and any(self.root.iterdir()) and not (self.work / 'state.json').exists():
            raise InstallError('Target is not empty and was not created by this installer. Choose a new --prefix.')
        if any(c.isspace() for c in str(self.root)):
            state = self.work / 'state.json'
            completed = state.is_file() and json.loads(state.read_text()).get('complete')
            if not completed:
                raise InstallError('Source builds require a --prefix without whitespace. After installation, the directory can be moved to a path with spaces.')
        missing = [tool for tool in ('cc', 'c++', 'make', 'm4', 'file', 'patch', 'perl', 'pkg-config', 'getconf', 'strip', 'readelf', 'ldd')
                   if not shutil.which(tool, path=self.env['PATH'])]
        if missing:
            raise InstallError('Missing bootstrap tools: ' + ', '.join(missing) + '. See README prerequisites.')
        libc = subprocess.check_output(['getconf', 'GNU_LIBC_VERSION'], text=True).strip()
        match = re.fullmatch(r'glibc (\d+)\.(\d+)', libc)
        if not match or tuple(map(int, match.groups())) < (2, 34):
            raise InstallError('This release requires Linux glibc >= 2.34; found: ' + libc)
        for path in (self.work, self.cache, self.work / 'tmp', self.work / 'logs', self.work / 'build',
                     self.root / 'bin', self.root / 'opt/lib', self.root / 'opt/include'):
            path.mkdir(parents=True, exist_ok=True)
        self.guard = (self.work / 'install.lock').open('a+')
        try:
            fcntl.flock(self.guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise InstallError('Another installer is already using this prefix')
        if (self.work / 'state.json').exists():
            old = json.loads((self.work / 'state.json').read_text())
            if old['lock_sha256'] != self.state['lock_sha256'] or old['architecture'] != self.arch:
                raise InstallError('Resume requires the same locked release and architecture; use a new prefix')
            self.state = old
        self.state['bootstrap'] = {'libc': libc, 'compiler': subprocess.check_output(['cc', '--version'], env=self.env, text=True).splitlines()[0]}
        self.prepared = True
        self.save()
        self.add_path(self.root / 'bin')
        self.add_path(self.root / 'opt/bin')
        print('Installing into:', self.root, '\nLogs:', self.work / 'logs', flush=True)

    def save(self):
        write_json(self.work / 'state.json', self.state)

    def event(self, kind, detail):
        with (self.work / 'events.jsonl').open('a', encoding='utf-8') as out:
            out.write(json.dumps({'time':time.strftime('%Y-%m-%dT%H:%M:%S%z'),
                                  'run':self.run_id, 'kind':kind, 'step':self.active_step,
                                  'detail':detail}, ensure_ascii=False) + '\n')

    def add_path(self, path):
        self.env['PATH'] = str(path) + ':' + self.env['PATH']

    def run(self, command, cwd=None, extra=None, capture=False, timeout=None):
        command = list(map(str, command))
        self.counter += 1
        log = self.work / 'logs' / ('%s-%05d-%s.log' % (self.run_id, self.counter, self.active_step or 'setup'))
        env = self.env.copy()
        env.update({k: str(v) for k, v in (extra or {}).items()})
        started = time.monotonic()
        with log.open('w', encoding='utf-8') as output:
            output.write('$ ' + shlex.join(command) + '\n')
            output.flush()
            process = subprocess.Popen(command, cwd=cwd, env=env, stdout=output, stderr=subprocess.STDOUT)
            try:
                while True:
                    try:
                        code = process.wait(timeout=15)
                        break
                    except subprocess.TimeoutExpired:
                        elapsed = int(time.monotonic() - started)
                        print('  %s: %ss; %s' % (self.active_step, elapsed, log.name), flush=True)
                        if timeout is not None and elapsed > timeout:
                            process.terminate()
                            raise InstallError('Command timeout, see ' + str(log))
            except BaseException:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                raise
        if code:
            tail = '\n'.join(log.read_text(errors='replace').splitlines()[-25:])
            raise InstallError('Command failed (%s): %s\n%s' % (code, log, tail))
        return log.read_text(errors='replace').partition('\n')[2] if capture else None

    def step(self, name, action, outputs):
        previous = self.state['steps'].get(name)
        outputs = [self.root / p for p in outputs]
        if previous and previous.get('__source_request',False) == (name in self.forced) and all(p.is_file() and digest(p) == previous.get(str(p.relative_to(self.root))) for p in outputs):
            print('REUSE', name, flush=True)
            return
        self.active_step = name
        print('BUILD', name, flush=True)
        self.event('start', name)
        self.state['active_step'] = name
        self.state.pop('error', None)
        if name in self.lock['components']:
            self.state.setdefault('installation_methods', {}).pop(name, None)
        self.save()
        action()
        if any(not p.is_file() for p in outputs):
            raise InstallError('Expected output missing after ' + name + ': ' + ', '.join(map(str, outputs)))
        self.state['steps'][name] = {str(p.relative_to(self.root)): digest(p) for p in outputs}
        self.state['steps'][name]['__source_request'] = name in self.forced
        if name in self.lock['components']:
            self.state.setdefault('installation_methods', {}).setdefault(name,
                'source' if 'source' in self.lock['components'][name] else 'pinned build-tool binary')
        self.state['active_step'] = None
        self.save()
        self.event('done', name)
        print('DONE', name, flush=True)

    def fetch(self, artifact):
        # A shared --cache may be used by two architecture/distro installs.
        # Serialize the same artifact; a partial file never becomes a cache hit.
        guard = self.cache / (artifact['sha256'] + '.lock')
        with guard.open('a+') as stream:
            fcntl.flock(stream, fcntl.LOCK_EX)
            return self._fetch_unlocked(artifact)

    def _fetch_unlocked(self, artifact):
        url, expected = artifact['url'], artifact['sha256']
        target = self.cache / expected
        if target.exists():
            if digest(target) != expected:
                raise InstallError('Cached download checksum mismatch: ' + str(target))
            return target
        temporary = target.with_suffix('.part')
        print('DOWNLOAD', url, flush=True)
        for attempt in range(3):
            try:
                curl = shutil.which('curl', path=self.env['PATH'])
                if curl:
                    # -q ignores personal curlrc; HTTP/1.1 also works through
                    # older enterprise proxies that truncate HTTP/2 transfers.
                    process = subprocess.Popen([curl, '-q', '--http1.1', '--fail', '--location', '--silent', '--show-error',
                        '--connect-timeout','20','--max-time','1800','--speed-limit','1024','--speed-time','60',
                        '--output',str(temporary),url], env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                    try:
                        while True:
                            try:
                                _, error = process.communicate(timeout=15)
                                break
                            except subprocess.TimeoutExpired:
                                print('  downloading:', temporary.stat().st_size if temporary.exists() else 0, 'bytes', flush=True)
                    except BaseException:
                        process.terminate(); process.communicate()
                        raise
                    if process.returncode:
                        if process.returncode == 22 and re.search(rb'\b(404|410)\b', error):
                            raise Unavailable('Locked artifact unavailable: ' + url)
                        raise ConnectionError(error.decode(errors='replace').strip())
                else:
                    request = urllib.request.Request(url, headers={'User-Agent': 'AstroNvim-source-installer/1.0'})
                    with urllib.request.urlopen(request, timeout=45) as response, temporary.open('wb') as out:
                        expected_size = response.headers.get('Content-Length')
                        shutil.copyfileobj(response, out, 1024 * 1024)
                    if expected_size and temporary.stat().st_size != int(expected_size):
                        raise ConnectionError('Truncated response: expected %s bytes, got %s' % (expected_size, temporary.stat().st_size))
                if digest(temporary) != expected:
                    temporary.unlink()
                    raise InstallError('SHA256 mismatch: ' + url + '; refusing this artifact')
                temporary.replace(target)
                return target
            except urllib.error.HTTPError as error:
                if error.code in (404, 410):
                    raise Unavailable('Locked artifact unavailable: ' + url)
                if attempt == 2:
                    raise InstallError('Download failed: %s: %s' % (url, error))
            except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
                if attempt == 2:
                    raise InstallError('Download failed: %s: %s; rerun to resume' % (url, error))
            time.sleep(attempt + 1)
        raise InstallError('Download failed: ' + url)

    def source(self, name):
        artifact = self.lock['components'][name]['source']
        directory = self.work / 'build' / (name + '-source')
        if not directory.exists():
            unpack = self.work / 'build' / (name + '-unpack')
            shutil.rmtree(unpack, ignore_errors=True)
            extract(self.fetch(artifact), unpack)
            children = list(unpack.iterdir())
            if len(children) == 1 and children[0].is_dir():
                children[0].rename(directory)
                unpack.rmdir()
            else:
                unpack.rename(directory)
        self.licenses(name, directory)
        return directory

    def licenses(self, name, source):
        destination = self.root / 'licenses' / name
        destination.mkdir(parents=True, exist_ok=True)
        for path in Path(source).iterdir():
            if path.is_file() and re.match(r'(?i)^(COPYING|COPYRIGHT|LICENSE|NOTICE)', path.name):
                shutil.copy2(path, destination / path.name)

    def patch(self, directory, entry):
        patch = HERE / entry['patch']
        if digest(patch) != entry['patch_sha256']:
            raise InstallError('Patch checksum mismatch: ' + str(patch))
        paths = entry['files']
        if all((directory / n).is_file() and digest(directory / n) == v['after'] for n, v in paths.items()):
            return
        for name, checks in paths.items():
            path = directory / name
            if checks['before'] is None:
                if path.exists():
                    raise InstallError('Unexpected file before patch: ' + str(path))
            elif not path.is_file() or digest(path) != checks['before']:
                raise InstallError('Upstream file differs from pinned patch base: ' + str(path))
        self.run(['patch', '--batch', '--forward', '--fuzz=0', '-p1', '-i', patch], cwd=directory)
        for name, checks in paths.items():
            if digest(directory / name) != checks['after']:
                raise InstallError('Patched content mismatch: ' + name)

    def make(self, source, targets=(), extra=None):
        self.run(['make', '-j' + str(self.jobs), 'MAKEINFO=true', *targets], cwd=source, extra=extra)

    def configure(self, name, options=(), prefix=None, extra=None):
        source = self.source(name)
        prefix = prefix or self.root / 'opt'
        self.run([source / 'configure', '--prefix=' + str(prefix), '--libdir=' + str(prefix / 'lib'), *options], cwd=source, extra=extra)
        self.make(source, extra=extra)
        self.make(source, ['install'], extra=extra)
        return source

    def probe(self, command, version):
        try:
            result = subprocess.run(list(map(str, command)), env=self.env, capture_output=True, text=True, timeout=20)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise Incompatible(str(error))
        text = result.stdout + result.stderr
        if result.returncode or version not in text:
            raise Incompatible('Binary failed version/loader probe: ' + text[-2000:])

    def link(self, name, target):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.is_symlink() or path.exists():
            path.unlink()
        path.symlink_to(os.path.relpath(self.root / target, path.parent))

    # Component recipes are attached below to keep bootstrap and download checks shared.


def options():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix', required=True, help='New installation directory (or resume this installer)')
    parser.add_argument('--jobs', type=int, default=2, help='Concurrent build jobs; default 2')
    parser.add_argument('--cache', help='Optional shared verified download cache')
    parser.add_argument('--from-source', default='', help='Comma-separated fixed-version source builds, e.g. neovim,tree-sitter')
    parser.add_argument('--plan', action='store_true', help='Print locked plan without installing')
    parser.add_argument('--architecture', choices=ARCHES, help='Override only for --plan; real builds must match host')
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error('--jobs must be >= 1')
    return args


def main():
    if sys.version_info < (3, 8):
        raise SystemExit('Python >= 3.8 required for the installer')
    args = options()
    install = None
    try:
        lock = lockfile()
        install = Installer(args, lock)
        if args.plan:
            print('Architecture:', install.arch, '| prefix:', install.root)
            for name, item in lock['components'].items():
                mode = ('binary (source fallback)' if 'source' in item else 'pinned binary') if install.arch in item.get('binaries', {}) and name not in install.forced else 'source'
                if item.get('build_only'):
                    mode += ' [build tool]'
                print('%-13s %-10s %s' % (name, item['version'], mode))
            print('Plugins: 35 exact commits; parsers: 10 exact commits; patches: checksum verified')
            return
        install.prepare()
        if install.state.get('complete'):
            print('This installation is already complete; configuration was left unchanged.\nsource ' + shlex.quote(str(install.root/'env.sh')))
            print('Use a new --prefix for a rebuild or different source-build options.')
            return
        install.all()
    except Exception as error:
        if install and install.prepared:
            install.state['error'] = str(error)
            install.save()
            install.event('error', str(error))
            import traceback
            (install.work / 'logs' / (install.run_id + '-failure.log')).write_text(traceback.format_exc())
        print('\nINSTALL FAILED: ' + str(error), file=sys.stderr, flush=True)
        raise SystemExit(1)
    except KeyboardInterrupt:
        print('\nInterrupted; repeat the same command to resume.', file=sys.stderr)
        raise SystemExit(130)


if __name__ == '__main__':
    # Recipes do not run at import time, which also allows offline installer tests.
    from recipes import install_recipes
    install_recipes(Installer)
    main()
