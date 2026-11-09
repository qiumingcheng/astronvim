"""Native x86_64/aarch64 build recipes; every downloaded input is locked."""
import concurrent.futures
import gzip
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile


def install_recipes(cls):
    # When launched as a script, __main__ already contains the shared types.
    import sys
    core = sys.modules[cls.__module__]
    HERE, InstallError = core.HERE, core.InstallError
    extract, digest, write_json = core.extract, core.digest, core.write_json

    def libraries(self):
        for name, options, output in [
            ('zlib', ['--static'], 'libz.a'),
            ('gmp', ['--disable-shared', '--enable-static', '--with-pic', '--disable-assembly'], 'libgmp.a'),
            ('mpfr', ['--disable-shared', '--enable-static', '--with-pic', '--with-gmp=' + str(self.root/'opt')], 'libmpfr.a'),
            ('expat', ['--disable-shared', '--enable-static', '--without-docbook', '--without-examples', '--without-tests'], 'libexpat.a'),
            ('libffi', ['--disable-shared', '--enable-static', '--with-pic', '--disable-docs', '--disable-multi-os-directory'], 'libffi.a'),
            ('xz', ['--disable-shared', '--enable-static', '--disable-doc'], 'liblzma.a'),
        ]:
            self.step(name, lambda n=name, o=options: self.configure(n, o), ['opt/lib/' + output])
        def bzip():
            source = self.source('bzip2')
            self.make(source, ['CFLAGS=-O2 -g0 -fPIC'])
            self.make(source, ['install', 'PREFIX=' + str(self.root/'opt')])
        self.step('bzip2', bzip, ['opt/lib/libbz2.a'])
        def ssl():
            source = self.source('openssl')
            self.run([source/'config', '--prefix=' + str(self.root/'opt'), '--libdir=lib',
                      '--openssldir=' + str(self.root/'opt/ssl'), 'no-shared', 'no-tests', '-fPIC'], cwd=source)
            self.make(source)
            self.make(source, ['install_sw'])
        self.step('openssl', ssl, ['opt/lib/libssl.a', 'opt/lib/libcrypto.a'])
        def curses():
            self.configure('ncurses', ['--with-shared', '--with-normal', '--enable-widec', '--without-debug',
                                      '--without-ada', '--without-cxx-binding', '--enable-pc-files',
                                      '--with-pkg-config-libdir=' + str(self.root/'opt/lib/pkgconfig')])
            # GDB's bundled readline probes the traditional tinfo/ncurses names.
            for name in ('ncurses', 'tinfo'):
                source = self.root/'opt/lib/libncursesw.so'
                self.link('opt/lib/lib' + name + '.so', str(source.relative_to(self.root)))
                self.link('opt/lib/lib' + name + '.a', 'opt/lib/libncursesw.a')
            for header in (self.root/'opt/include/ncursesw').glob('*.h'):
                self.link('opt/include/' + header.name, str(header.relative_to(self.root)))
        self.step('ncurses', curses, ['opt/lib/libncursesw.so.6', 'opt/bin/tic'])

    def python(self):
        source = self.source('python')
        # This interpreter serves GDB/DAP. Avoid accidental host-only optional
        # desktop/database modules; all enabled compression/SSL/ffi libs are private.
        disabled = ('_tkinter','_sqlite3','_dbm','_gdbm','nis','readline','_curses','_curses_panel','_crypt','_uuid')
        (source/'Modules/Setup.local').write_text('*disabled*\n' + '\n'.join(disabled) + '\n')
        for name in disabled:
            for path in source.glob('build/lib.*/' + name + '.*.so'):
                path.unlink()
        self.run([source/'configure', '--prefix=' + str(self.root/'opt/python'), '--enable-shared',
                  '--with-ensurepip=no', '--with-system-expat', '--with-system-ffi',
                  '--with-openssl=' + str(self.root/'opt')], cwd=source)
        self.make(source)
        self.make(source, ['install'])
        for name in disabled:
            for path in (self.root/'opt/python/lib/python3.9/lib-dynload').glob(name + '.*.so'):
                path.unlink()
        self.link('opt/lib/libpython3.9.so.1.0', 'opt/python/lib/libpython3.9.so.1.0')
        self.link('opt/lib/libpython3.9.so', 'opt/python/lib/libpython3.9.so')
        self.run([self.root/'opt/python/bin/python3.9', '-c',
                  'import ssl,ctypes,zlib,lzma,bz2,socket,select,asyncio,json; print(ssl.OPENSSL_VERSION)'])

    def gdb(self):
        source = self.source('gdb')
        build = self.work/'build/gdb-build'
        build.mkdir(exist_ok=True)
        self.run([source/'configure', '--prefix=' + str(self.root/'opt/gdb'),
                  '--with-python=' + str(self.root/'opt/python/bin/python3.9'),
                  '--with-gmp=' + str(self.root/'opt'), '--with-mpfr=' + str(self.root/'opt'),
                  '--with-expat', '--with-libexpat-prefix=' + str(self.root/'opt'),
                  '--with-system-readline=no', '--disable-nls', '--disable-werror', '--disable-sim',
                  '--disable-gprofng', '--disable-binutils', '--disable-gas', '--disable-ld', '--disable-gold',
                  '--without-guile', '--without-debuginfod', '--without-intel-pt', '--disable-source-highlight'], cwd=build)
        self.make(build, ['MAKEINFO=true'])
        self.make(build, ['install', 'MAKEINFO=true'])
        self.run(['strip', self.root/'opt/gdb/bin/gdb'])
        self.patch(self.root, json.loads((HERE/'patches.lock.json').read_text())['gdb'])

    def utilities(self):
        self.step('curl', lambda: self.configure('curl', [
            '--with-openssl=' + str(self.root/'opt'), '--with-zlib=' + str(self.root/'opt'),
            '--disable-shared', '--enable-static', '--disable-ldap', '--disable-ldaps', '--without-libpsl',
            '--without-libidn2', '--without-libssh2', '--without-brotli', '--without-zstd', '--without-nghttp2',
            '--without-gssapi', '--disable-docs', '--without-librtmp']), ['opt/bin/curl', 'opt/lib/libcurl.a'])
        def git():
            source = self.source('git')
            opts = ['prefix=' + str(self.root/'opt/git'), 'gitexecdir=' + str(self.root/'opt/git/libexec'),
                    'template_dir=' + str(self.root/'opt/git/templates'), 'NO_GETTEXT=YesPlease', 'NO_TCLTK=YesPlease',
                    'NO_PERL=YesPlease', 'NO_PYTHON=YesPlease', 'CURL_CONFIG=' + str(self.root/'opt/bin/curl-config'),
                    'CURLDIR=' + str(self.root/'opt'), 'OPENSSLDIR=' + str(self.root/'opt'), 'ZLIB_PATH=' + str(self.root/'opt')]
            self.make(source, opts)
            self.make(source, ['install', *opts])
        self.step('git', git, ['opt/git/bin/git', 'opt/git/libexec/git-remote-http'])
        self.env['GIT_EXEC_PATH'] = str(self.root/'opt/git/libexec')
        self.env['GIT_TEMPLATE_DIR'] = str(self.root/'opt/git/templates')
        self.add_path(self.root/'opt/git/bin')
        for name in ('gzip', 'tar'):
            self.step(name, lambda n=name: self.configure(n, extra={'FORCE_UNSAFE_CONFIGURE':'1'}), ['opt/bin/'+name])
        def unzip():
            source = self.source('unzip')
            self.make(source, ['-f', 'unix/Makefile', 'generic', 'CC=cc', 'CFLAGS=-O2 -D_FILE_OFFSET_BITS=64'])
            shutil.copy2(source/'unzip', self.root/'opt/bin/unzip')
        self.step('unzip', unzip, ['opt/bin/unzip'])
        for command in ('tar', 'gzip', 'curl', 'unzip'):
            self.link('bin/' + command, 'opt/bin/' + command)
        self.link('bin/git', 'opt/git/bin/git')

    def certificate(self):
        # Trust anchors are host policy, not an executable dependency or a release.
        # Snapshot them so an installed tree still works after moving to another host.
        for path in ('/etc/ssl/certs/ca-certificates.crt', '/etc/pki/tls/certs/ca-bundle.crt',
                     '/etc/ssl/ca-bundle.pem', '/etc/ssl/cert.pem'):
            if Path(path).is_file():
                target = self.root/'opt/certs/ca-bundle.crt'
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, target)
                self.state['trust_store'] = {'source':path, 'sha256':digest(target)}
                self.env['GIT_SSL_CAINFO'] = str(target)
                self.env['CURL_CA_BUNDLE'] = str(target)
                return
        raise InstallError('No system HTTPS trust store found; install ca-certificates first')

    def binary(self, name, destination, executable, version, options=('--version',)):
        """Return false only for an absent/incompatible same-version artifact."""
        component = self.lock['components'][name]
        artifact = component.get('binaries', {}).get(self.arch)
        if not artifact or name in self.forced:
            return False
        try:
            download = self.fetch(artifact)
            temporary = self.work/'build'/(name+'-binary')
            shutil.rmtree(temporary, ignore_errors=True)
            temporary.mkdir()
            if name == 'tree-sitter':
                with gzip.open(download, 'rb') as source, (temporary/'tree-sitter').open('wb') as out:
                    shutil.copyfileobj(source, out)
                (temporary/'tree-sitter').chmod(0o755)
                tree = temporary
            else:
                extract(download, temporary)
                children = list(temporary.iterdir())
                tree = children[0] if name != 'codelldb' and len(children) == 1 and children[0].is_dir() else temporary
            # Probe before replacing a completed installation directory.
            if name == 'codelldb':
                # CodeLLDB has --help, but deliberately no --version option.
                package_version = json.loads((tree/'extension/package.json').read_text())['version']
                if package_version != version:
                    raise InstallError('CodeLLDB package version mismatch: ' + package_version)
                self.probe([tree/executable, '--help'], 'Usage: codelldb')
            else:
                self.probe([tree/executable, *options], version)
            target = self.root/destination
            shutil.rmtree(target, ignore_errors=True)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(tree, target, symlinks=True)
            self.licenses(name, tree)
            self.state.setdefault('installation_methods', {})[name] = 'upstream binary'
            return True
        except (core.Unavailable, core.Incompatible) as error:
            print('SOURCE FALLBACK:', name, str(error), flush=True)
            self.state.setdefault('fallbacks', {})[name] = str(error)
            return False

    def tools(self):
        def cmake():
            if self.binary('cmake', '.installer/tools/cmake', 'bin/cmake', '3.31.8'):
                return
            source = self.source('cmake')
            self.run([source/'bootstrap', '--prefix=' + str(self.work/'tools/cmake'), '--parallel=' + str(self.jobs),
                      '--', '-DCMAKE_USE_OPENSSL=OFF'], cwd=source)
            self.make(source)
            self.make(source, ['install'])
        self.step('cmake', cmake, ['.installer/tools/cmake/bin/cmake'])
        self.add_path(self.work/'tools/cmake/bin')
        def ninja():
            source = self.source('ninja')
            self.run([sys.executable, source/'configure.py', '--bootstrap'], cwd=source)
            target = self.work/'tools/bin/ninja'
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source/'ninja', target)
        self.step('ninja', ninja, ['.installer/tools/bin/ninja'])
        self.add_path(self.work/'tools/bin')
        def rust():
            artifact = self.lock['components']['rust']['binaries'][self.arch]
            source = self.work/'build/rust-dist'
            if not source.exists():
                extract(self.fetch(artifact), source)
            tree = next(source.iterdir())
            self.run(['bash', tree/'install.sh', '--prefix=' + str(self.work/'tools/rust'),
                      '--components=rustc,cargo,rust-std-' + self.arch + '-unknown-linux-gnu', '--disable-ldconfig'])
        self.step('rust', rust, ['.installer/tools/rust/bin/rustc', '.installer/tools/rust/bin/cargo'])
        self.add_path(self.work/'tools/rust/bin')
        self.probe(['rustc', '--version'], '1.91.0')
        # Bear's interceptor links with rust-lld. Resolve the bundled executable
        # explicitly; do not rely on a system LLVM or a globally selected rustup.
        lld = self.work/'tools/rust/lib/rustlib'/ (self.arch+'-unknown-linux-gnu') / 'bin/rust-lld'
        if lld.exists():
            link = self.work/'tools/bin/ld.lld'
            if not link.exists():
                link.symlink_to(os.path.relpath(lld, link.parent))

    def cargo(self, name, executable, destination, package=None):
        if self.binary(name, destination, executable, self.lock['components'][name]['version']):
            return
        source = self.source(name)
        lock = source/'Cargo.lock'
        if not lock.is_file():
            raise InstallError('No Cargo.lock in pinned source: ' + name)
        before = digest(lock)
        self.run(['cargo', 'build', '--release', '--locked', '--jobs', self.jobs,
                  *(['--package', package] if package else [])], cwd=source)
        if digest(lock) != before:
            raise InstallError('Cargo modified the lock file: ' + name)
        target = self.root/destination
        target.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source/'target/release'/executable, target/executable)
        self.run(['strip', target/executable])

    def bear(self):
        source = self.source('bear')
        before = digest(source/'Cargo.lock')
        self.run(['cargo', 'build', '--release', '--locked', '--jobs', self.jobs], cwd=source,
                 extra={'INTERCEPT_LIBDIR':'lib'})
        if digest(source/'Cargo.lock') != before:
            raise InstallError('Bear Cargo.lock changed')
        self.run(['sh', source/'scripts/install.sh'], cwd=source,
                 extra={'PREFIX':self.root/'opt/bear', 'INTERCEPT_LIBDIR':'lib'})
        wrapper = self.root/'opt/bear/bin/bear'
        wrapper.write_text('#!/bin/sh\nexec "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/libexec/bear/bin/bear-driver" "$@"\n')
        wrapper.chmod(0o755)
        self.probe([wrapper, '--version'], '4.2.2')

    def neovim(self):
        if not self.binary('neovim', 'opt/nvim', 'bin/nvim', 'v0.12.5'):
            source = self.source('neovim')
            self.make(source, ['CMAKE_BUILD_TYPE=Release', 'CMAKE_INSTALL_PREFIX=' + str(self.root/'opt/nvim')])
            self.make(source, ['install', 'CMAKE_BUILD_TYPE=Release', 'CMAKE_INSTALL_PREFIX=' + str(self.root/'opt/nvim')])
        self.patch(self.root, json.loads((HERE/'patches.lock.json').read_text())['neovim'])

    def llvm(self, component, lldb=False):
        source = self.source(component)
        build = self.work/'build'/(component+'-build')
        prefix = self.root/('opt/codelldb/extension/lldb' if lldb else 'opt/clangd')
        options = ['-DLLVM_ENABLE_PROJECTS=' + ('clang;lldb' if lldb else 'clang;clang-tools-extra'),
                   '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_INSTALL_PREFIX=' + str(prefix),
                   '-DLLVM_TARGETS_TO_BUILD=Native', '-DLLVM_INCLUDE_TESTS=OFF', '-DLLVM_INCLUDE_BENCHMARKS=OFF',
                   '-DLLVM_INCLUDE_EXAMPLES=OFF', '-DCLANG_INCLUDE_TESTS=OFF', '-DLLVM_ENABLE_ZLIB=ON',
                   '-DLLVM_ENABLE_ZSTD=OFF', '-DLLVM_ENABLE_LIBXML2=OFF', '-DLLVM_ENABLE_TERMINFO=OFF',
                   '-DLLVM_ENABLE_LIBEDIT=OFF', '-DLLVM_PARALLEL_LINK_JOBS=1',
                   '-DLLVM_ENABLE_BINDINGS=OFF', '-DLLVM_ENABLE_RTTI=ON']
        if lldb:
            options += ['-DLLDB_INCLUDE_TESTS=OFF', '-DLLDB_ENABLE_PYTHON=ON', '-DLLDB_ENABLE_LUA=OFF',
                        '-DLLDB_ENABLE_LIBEDIT=OFF', '-DLLDB_ENABLE_CURSES=OFF', '-DLLDB_ENABLE_LIBXML2=OFF',
                        '-DSWIG_EXECUTABLE=' + str(self.root/'opt/bin/swig'),
                        '-DPython3_EXECUTABLE=' + str(self.root/'opt/python/bin/python3.9'),
                        '-DPython3_ROOT_DIR=' + str(self.root/'opt/python')]
        self.run(['cmake', '-S', source/'llvm', '-B', build, '-G', 'Ninja', *options])
        targets = ['lldb', 'lldb-server', 'liblldb'] if lldb else ['clangd']
        self.run(['cmake', '--build', build, '--parallel', self.jobs, '--target', *targets])
        install_targets = ['install-lldb', 'install-lldb-server', 'install-liblldb', 'install-lldb-python-scripts'] if lldb else ['install-clangd', 'install-clang-resource-headers']
        self.run(['cmake', '--build', build, '--parallel', self.jobs, '--target', *install_targets])
        return source, build

    def clangd(self):
        if not self.binary('clangd', 'opt/clangd', 'bin/clangd', '22.1.6'):
            self.llvm('clangd')
        self.probe([self.root/'opt/clangd/bin/clangd', '--version'], '22.1.6')

    def codelldb(self):
        if self.binary('codelldb', 'opt/codelldb', 'extension/adapter/codelldb', '1.12.3'):
            return
        self.step('pcre2', lambda: self.configure('pcre2', ['--disable-shared', '--enable-static', '--with-pic']), ['opt/lib/libpcre2-8.a'])
        self.step('swig', lambda: self.configure('swig', ['--without-alllang', '--with-python3=' + str(self.root/'opt/python/bin/python3.9')]), ['opt/bin/swig'])
        def node():
            if not self.binary('node', '.installer/tools/node', 'bin/node', 'v22.14.0'):
                raise InstallError('Pinned build tool Node 22.14.0 is unavailable for this supported platform')
        self.step('node', node, ['.installer/tools/node/bin/node'])
        self.add_path(self.work/'tools/node/bin')
        llvm_source, llvm_build = self.llvm('lldb', lldb=True)
        source = self.source('codelldb')
        # These build-only adaptations retain dependency locks and use the same
        # C++ ABI as the LLDB we just built with the native compiler.
        cmake = source/'CMakeLists.txt'
        text = cmake.read_text().replace('COMMAND ${NPM} install', 'COMMAND ${NPM} ci')
        text = text.replace('set(CargoFlags ${CargoFlags} --manifest-path=', 'set(CargoFlags ${CargoFlags} --locked --manifest-path=')
        text = text.replace('COMMAND cargo run --package', 'COMMAND cargo run --locked --package')
        cmake.write_text(text)
        adapter = source/'adapter/CMakeLists.txt'
        text = adapter.read_text().replace('-Clink-arg=-fuse-ld=lld', '').replace('-Clink-arg=-Wl,-Bstatic,-lc++,-lc++abi,-Bdynamic', '-Clink-arg=-lstdc++')
        adapter.write_text(text)
        toolchain = self.work/'build/codelldb-native.cmake'
        toolchain.write_text('set(LLVM_TRIPLE '+self.arch+'-unknown-linux-gnu)\nset(CMAKE_C_COMPILER cc)\nset(CMAKE_CXX_COMPILER c++)\n')
        build = self.work/'build/codelldb-build'
        self.run(['cmake', '-S', source, '-B', build, '-G', 'Ninja', '-DCMAKE_BUILD_TYPE=Release',
                  '-DCMAKE_TOOLCHAIN_FILE=' + str(toolchain), '-DVERSION_SUFFIX=',
                  '-DLLDB_PACKAGE=' + str(llvm_build), '-DLLVM_SOURCE_DIR=' + str(llvm_source),
                  '-DPLATFORM_ID=linux-' + ('x64' if self.arch=='x86_64' else 'arm64')])
        self.run(['cmake', '--build', build, '--parallel', self.jobs, '--target', 'adapter'])
        target = self.root/'opt/codelldb/extension'
        (target/'adapter').mkdir(parents=True,exist_ok=True)
        shutil.copy2(build/'adapter/codelldb',target/'adapter/codelldb')
        for path in (build/'adapter').glob('*.so*'):
            shutil.copy2(path,target/'adapter'/path.name)
        for name in ('adapter/scripts','lang_support'):
            for path in (build/name).rglob('*.py'):
                out=target/name/path.relative_to(build/name)
                out.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(path,out)
        if (build/'bin/codelldb-launch').exists():
            (target/'bin').mkdir(exist_ok=True)
            shutil.copy2(build/'bin/codelldb-launch',target/'bin/codelldb-launch')
        # Source-built LLDB uses our private Python. Its wrapper is installed at finalization.
        self.state['codelldb_source_python'] = True

    def git_source(self, item, target):
        target = Path(target)
        if (target/'.git').exists():
            probe = subprocess.run(['git', '-C', str(target), 'rev-parse', '--verify', 'HEAD'], env=self.env, capture_output=True, text=True)
            if probe.returncode == 0:
                if probe.stdout.strip() != item['commit']:
                    raise InstallError('Existing checkout has the wrong commit: ' + str(target))
                return
            # Interrupted before checkout: retain fetched objects and retry the
            # same commit; an empty Git directory must not break resume forever.
        else:
            if target.exists():
                shutil.rmtree(target)
            target.mkdir(parents=True)
            self.run(['git', 'init', '--quiet', target])
        self.run(['git', '-C', target, 'config', 'remote.origin.url', item['url']])
        self.run(['git', '-C', target, '-c', 'advice.detachedHead=false', '-c', 'http.lowSpeedLimit=1024',
                  '-c', 'http.lowSpeedTime=60', 'fetch', '--depth=1', 'origin', item['commit']], timeout=300)
        self.run(['git', '-C', target, 'checkout', '--quiet', '--detach', item['commit']])
        if self.run(['git', '-C', target, 'rev-parse', 'HEAD'], capture=True).strip() != item['commit']:
            raise InstallError('Fetched commit mismatch: ' + item['name'])

    def plugins(self):
        for item in json.loads((HERE/'plugins.lock.json').read_text()):
            target = self.root/'data/nvim/lazy'/item['name']
            self.git_source(item, target)
            if item.get('patch'):
                self.patch(target, item)
            self.licenses(item['name'], target)

    def parsers(self):
        target = self.root/'data/nvim/site/parser'
        target.mkdir(parents=True, exist_ok=True)
        for item in json.loads((HERE/'parsers.lock.json').read_text()):
            source = self.work/'build'/('parser-' + item['commit'])
            self.git_source(item, source)
            self.licenses('tree-sitter-' + item['name'], source)
            grammar = source/item['directory']
            inputs = [grammar/'src/parser.c']
            inputs += [p for p in (grammar/'src/scanner.c', grammar/'src/scanner.cc') if p.exists()]
            objects = []
            for path in inputs:
                obj = grammar/(path.name + '.o')
                self.run(['c++' if path.suffix=='.cc' else 'cc', '-O2', '-fPIC', '-I', grammar/'src', '-c', path, '-o', obj])
                objects.append(obj)
            self.run(['c++' if any(p.suffix=='.cc' for p in inputs) else 'cc', '-shared', *objects, '-o', target/(item['name']+'.so')])

    def terminfo(self):
        destination = self.root/'opt/terminfo'
        destination.mkdir(parents=True, exist_ok=True)
        compat = self.root/'opt/terminfo-compat'
        compat.mkdir(parents=True, exist_ok=True)
        for name in ('xterm', 'xterm-256color', 'screen-256color', 'tmux-256color'):
            source = self.run([self.root/'opt/bin/infocmp', '-1', name], capture=True,
                              extra={'TERMINFO':self.root/'opt/share/terminfo'})
            text = self.work/'build'/(name+'.terminfo')
            text.write_text(source)
            self.run([self.root/'opt/bin/tic', '-x', '-o', destination, text])
            # Preserve the SSH/PowerShell repaint fix: never scroll a rectangle
            # via terminal margin operations that can paint into neighboring panes.
            disabled = {'csr','ind','indn','ri','rin','il','il1','dl','dl1','smglr','smglp','smgrp','smgtb','smgtp','smgbp'}
            lines = []
            for line in source.splitlines():
                key = line.strip().split('=')[0].rstrip(',@')
                if key in disabled:
                    lines.append('\t' + key + '@,')
                elif key == 'cud1':
                    lines.append('\tcud1=\\E[B,')
                else:
                    lines.append(line)
            text.write_text('\n'.join(lines) + '\n')
            self.run([self.root/'opt/bin/tic', '-x', '-o', compat, text])
        (compat/'VERSION').write_text('ncurses 6.5; AstroNvim portable scrolling compatibility\n')

    def relocatable_links(self):
        # Some upstream Makefiles (notably bzip2) install absolute symlinks.
        # Convert only links into this installation; never retain host/build links.
        for path in (self.root/'opt').rglob('*'):
            if not path.is_symlink():
                continue
            target = path.resolve()
            if not core.inside(target, self.root) or core.inside(target, self.work) or not target.exists():
                raise InstallError('Non-portable runtime symlink: ' + str(path) + ' -> ' + os.readlink(path))
            if Path(os.readlink(path)).is_absolute():
                path.unlink()
                path.symlink_to(os.path.relpath(target,path.parent))

    def runtime(self):
        self.relocatable_links()
        glibc = re.compile(r'^(ld-linux|lib(c|m|dl|pthread|rt|resolv|util|anl|nss_\w+)\.so)')
        copied = {}
        minimum_glibc = (2,34)
        # ldd reports the transitive closure. Record host compiler runtimes, while
        # libraries we compiled above remain fixed by dependencies.lock.json.
        for path in list((self.root/'opt').rglob('*')):
            if path.is_symlink() or not path.is_file():
                continue
            with path.open('rb') as f:
                header = f.read(20)
                if header[:4] != b'\x7fELF':
                    continue
            machine = int.from_bytes(header[18:20], 'little' if header[5]==1 else 'big')
            if machine != {'x86_64':62,'aarch64':183}[self.arch]:
                raise InstallError('Wrong ELF architecture: ' + str(path))
            symbols = subprocess.run(['readelf','--version-info',str(path)], env=self.env, text=True, capture_output=True)
            for major,minor in re.findall(r'Name: GLIBC_(\d+)\.(\d+)',symbols.stdout):
                minimum_glibc = max(minimum_glibc,(int(major),int(minor)))
            result = subprocess.run(['ldd', str(path)], env=self.env, text=True, capture_output=True)
            output = result.stdout + result.stderr
            if 'not found' in output:
                raise InstallError('Runtime dependency unresolved: ' + str(path) + '\n' + output)
            for name, source in re.findall(r'\s+(\S+) => (/\S+) \(', output):
                if core.inside(source, self.root) or glibc.match(name):
                    continue
                dest = self.root/'opt/lib'/name
                if dest.exists() and digest(dest) != digest(source):
                    raise InstallError('Conflicting runtime library: ' + name)
                shutil.copy2(source, dest)
                copied[name] = {'build_host_path':source, 'sha256':digest(dest)}
                symbols = subprocess.run(['readelf','--version-info',str(dest)],env=self.env,text=True,capture_output=True)
                for major,minor in re.findall(r'Name: GLIBC_(\d+)\.(\d+)',symbols.stdout):
                    minimum_glibc = max(minimum_glibc,(int(major),int(minor)))
        write_json(self.root/'runtime-libraries.json', {'system_boundary':'glibc/loader', 'host_runtime_closure':copied})
        (self.root/'minimum-glibc').write_text('%s.%s\n' % minimum_glibc)
        # Retain host runtime copyright notices without assuming RPM or Debian.
        notices = self.root/'licenses/bootstrap-runtime'
        notices.mkdir(parents=True,exist_ok=True)
        for pattern in ('/usr/share/licenses/libgcc*','/usr/share/licenses/libstdc++*',
                        '/usr/share/licenses/gcc*','/usr/share/doc/gcc-*-base/copyright',
                        '/usr/share/doc/libstdc++*/copyright','/usr/share/doc/libgcc*/copyright'):
            import glob
            for filename in glob.glob(pattern):
                path = Path(filename)
                if path.is_file():
                    shutil.copy2(path,notices/(path.parent.name+'-'+path.name))
                elif path.is_dir():
                    shutil.copytree(path,notices/path.name,dirs_exist_ok=True)

    def overlay(self):
        shutil.copytree(HERE/'overlay', self.root, dirs_exist_ok=True, symlinks=True)
        # Restore the old package's names for every runtime dependency.
        for name, path in {'astronvim':'bin/astro', 'clangd':'opt/clangd/bin/clangd', 'rg':'opt/ripgrep/rg',
                           'fd':'opt/fd/fd', 'tree-sitter':'opt/tree-sitter/tree-sitter'}.items():
            self.link('bin/'+name, path)
        if self.state.get('codelldb_source_python'):
            path = self.root/'bin/codelldb'
            if path.is_symlink():
                path.unlink()
            path.write_text('#!/usr/bin/env bash\nset -euo pipefail\nroot=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)\nexport PYTHONHOME="$root/opt/python"\nexport LD_LIBRARY_PATH="$root/opt/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"\nexec "$root/opt/codelldb/extension/adapter/codelldb" "$@"\n')
            path.chmod(0o755)
        else:
            self.link('bin/codelldb', 'opt/codelldb/extension/adapter/codelldb')
        (self.root/'platform-architecture').write_text(self.arch+'\n')
        for directory in ('tmp', 'cache', 'state'):
            (self.root/directory).mkdir(exist_ok=True)
        vsix = self.root/'vscode/astronvim-terminal-keys.vsix'
        with zipfile.ZipFile(vsix, 'w', zipfile.ZIP_DEFLATED) as z:
            for path in sorted((HERE/'vscode-extension').rglob('*')):
                if path.is_file():
                    z.write(path, str(path.relative_to(HERE/'vscode-extension')))
        for file in ('dependencies.lock.json', 'plugins.lock.json', 'parsers.lock.json', 'patches.lock.json'):
            shutil.copy2(HERE/file, self.root/file)
        write_json(self.root/'versions.json', [{'name':n,'version':v['version'], **v} for n,v in self.lock['components'].items()])
        write_json(self.root/'installation-provenance.json', {'release':self.lock['release'], 'architecture':self.arch,
                   'bootstrap':self.state['bootstrap'], 'methods':self.state.get('installation_methods',{}),
                   'fallbacks':self.state.get('fallbacks',{}), 'trust_store':self.state.get('trust_store'),
                   'source_package_lock':digest(HERE/'dependencies.lock.json')})
        self.run([self.root/'opt/nvim/bin/nvim', '--headless', '-u', 'NONE',
                  '+set rtp+=' + str(self.root/'data/nvim/lazy/*'), '+helptags ALL', '+qa!'])

    def all_(self):
        self.certificate()
        self.libraries()
        self.step('python', self.python, ['opt/python/bin/python3.9', 'opt/python/lib/libpython3.9.so.1.0'])
        self.step('gdb', self.gdb, ['opt/gdb/bin/gdb', 'opt/gdb/share/gdb/python/gdb/dap/breakpoint.py'])
        self.utilities()
        self.tools()
        self.step('neovim', self.neovim, ['opt/nvim/bin/nvim', 'opt/nvim/share/nvim/runtime/lua/vim/loader.lua'])
        self.step('ripgrep', lambda: self.cargo('ripgrep','rg','opt/ripgrep'), ['opt/ripgrep/rg'])
        self.step('fd', lambda: self.cargo('fd','fd','opt/fd'), ['opt/fd/fd'])
        self.step('tree-sitter', lambda: self.cargo('tree-sitter','tree-sitter','opt/tree-sitter'), ['opt/tree-sitter/tree-sitter'])
        self.step('bear', self.bear, ['opt/bear/libexec/bear/bin/bear-driver', 'opt/bear/libexec/bear/lib/libexec.so'])
        self.step('clangd', self.clangd, ['opt/clangd/bin/clangd'])
        self.step('codelldb', self.codelldb, ['opt/codelldb/extension/adapter/codelldb'])
        self.active_step = 'plugins'
        self.plugins()
        self.active_step = 'parsers'
        self.parsers()
        self.step('terminfo', self.terminfo, ['opt/terminfo-compat/x/xterm-256color'])
        self.active_step = 'runtime'
        self.runtime()
        self.active_step = 'overlay'
        self.overlay()
        self.active_step = 'check'
        self.run(['bash', '-c', 'source "$1/env.sh"; exec "$1/bin/astro-check"', 'astro-check', self.root],
                 extra={'TERM':'xterm-256color','TERM_PROGRAM':'','WT_SESSION':''}, timeout=120)
        self.state['complete'] = True
        self.state['active_step'] = None
        self.state.pop('error',None)
        self.save()
        print('\nInstallation and smoke checks passed.\nsource ' + core.shlex.quote(str(self.root/'env.sh')) + '\nastronvim <project-directory>', flush=True)

    for name, function in list(locals().items()):
        if callable(function) and getattr(function,'__module__',None) == __name__:
            setattr(cls, 'all' if name=='all_' else name, function)
