#!/usr/bin/env python3
"""Offline tests for failures that must not be hidden by source fallback."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import io
import json
import os
import tarfile
import tempfile
import unittest
from unittest import mock
import zipfile
import sys

SOURCE = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(SOURCE))
import installer as module
from recipes import install_recipes
install_recipes(module.Installer)


class InstallerTests(unittest.TestCase):
    def setUp(self):
        # A sourced, relocated AstroNvim may set TMPDIR to a path with spaces.
        # Ordinary build fixtures need a valid prefix; whitespace has its own test.
        self.tmp = tempfile.TemporaryDirectory(prefix='astro-installer-test-',dir='/tmp')
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)
        self.lock = module.lockfile()
        args = argparse.Namespace(prefix=str(self.path/'install'), cache=str(self.path/'cache'),
                                  jobs=2, architecture=None, from_source='', plan=False)
        self.install = module.Installer(args,self.lock)
        self.install.cache.mkdir()

    def test_lock_has_same_native_versions_for_both_architectures(self):
        expected = {'neovim':'0.12.5','gdb':'17.2','clangd':'22.1.6','codelldb':'1.12.3',
                    'ripgrep':'15.2.0','fd':'10.5.0','bear':'4.2.2','tree-sitter':'0.26.6'}
        for name,version in expected.items():
            self.assertEqual(self.lock['components'][name]['version'], version)
        self.assertNotIn('aarch64', self.lock['components']['clangd'].get('binaries',{}))
        self.assertIn('source', self.lock['components']['clangd'])
        pins = json.loads((SOURCE/'plugins.lock.json').read_text())
        self.assertEqual(len(pins),35)
        lazy = json.loads((SOURCE/'overlay/config/nvim/lazy-lock.json').read_text())
        for p in pins:
            self.assertEqual(p['commit'],lazy[p['name']]['commit'])

    def test_corrupt_download_stops_instead_of_source_fallback(self):
        artifact={'url':'https://example.invalid/fixed-1.0.tar.gz','sha256':hashlib.sha256(b'correct').hexdigest()}
        response=io.BytesIO(b'corrupt')
        response.headers={}
        with mock.patch.object(module.urllib.request,'urlopen',return_value=response), mock.patch.object(module.shutil,'which',return_value=None):
            with self.assertRaisesRegex(module.InstallError,'SHA256 mismatch'):
                self.install.fetch(artifact)
        self.assertFalse((self.install.cache/artifact['sha256']).exists())

    def test_truncated_http_response_retries_without_accepting_partial_file(self):
        artifact={'url':'https://example.invalid/fixed','sha256':hashlib.sha256(b'abc').hexdigest()}
        responses=[]
        for _ in range(3):
            stream=io.BytesIO(b'abc');stream.headers={'Content-Length':'100'};responses.append(stream)
        with mock.patch.object(module.urllib.request,'urlopen',side_effect=responses) as request, mock.patch.object(module.time,'sleep'), mock.patch.object(module.shutil,'which',return_value=None):
            with self.assertRaisesRegex(module.InstallError,'Truncated response'):
                self.install.fetch(artifact)
        self.assertEqual(request.call_count,3)
        self.assertFalse((self.install.cache/artifact['sha256']).exists())

    def test_corrupt_cache_is_not_silently_trusted(self):
        artifact={'url':'https://example.invalid/fixed','sha256':'0'*64}
        (self.install.cache/artifact['sha256']).write_bytes(b'corrupt')
        with self.assertRaisesRegex(module.InstallError,'checksum mismatch'):
            self.install.fetch(artifact)

    def test_no_overwrite_of_unrelated_installation(self):
        self.install.root.mkdir()
        sentinel=self.install.root/'user-file'
        sentinel.write_text('preserve')
        with self.assertRaisesRegex(module.InstallError,'not empty'):
            self.install.prepare()
        self.assertEqual(sentinel.read_text(),'preserve')

    def test_tar_traversal_and_symlink_escape_rejected(self):
        for name,link in [('../outside',None),('link','../../outside')]:
            archive=self.path/'bad.tar'
            with tarfile.open(archive,'w') as tar:
                entry=tarfile.TarInfo(name)
                if link:
                    entry.type=tarfile.SYMTYPE;entry.linkname=link;tar.addfile(entry)
                else:
                    entry.size=3;tar.addfile(entry,io.BytesIO(b'bad'))
            with self.assertRaises(module.InstallError):
                module.extract(archive,self.path/'unpack')
        self.assertFalse((self.path/'outside').exists())

    def test_zip_permissions_and_safe_relative_links(self):
        archive=self.path/'good.zip'
        with zipfile.ZipFile(archive,'w') as z:
            info=zipfile.ZipInfo('bin/tool');info.external_attr=0o100755 << 16
            z.writestr(info,b'#!/bin/sh\n')
            info=zipfile.ZipInfo('bin/link');info.external_attr=0o120777 << 16
            z.writestr(info,b'tool')
        module.extract(archive,self.path/'unpack')
        self.assertTrue(os.access(self.path/'unpack/bin/tool',os.X_OK))
        self.assertEqual(os.readlink(self.path/'unpack/bin/link'),'tool')

    def test_source_archive_does_not_need_global_cargo_or_pythonhome(self):
        with mock.patch.dict(os.environ,{'PYTHONHOME':'/bad','LD_LIBRARY_PATH':'/oracle',
                                         'CARGO_HOME':'/old','RUSTC_WRAPPER':'/bad'}):
            other=module.Installer(self.install.args,self.lock)
        self.assertNotIn('PYTHONHOME',other.env)
        self.assertNotIn('RUSTC_WRAPPER',other.env)
        self.assertNotIn('oracle',other.env['LD_LIBRARY_PATH'])
        self.assertTrue(other.env['CARGO_HOME'].startswith(str(other.root)))

    def test_resume_checks_outputs_and_honors_forced_source(self):
        self.install.prepare()
        self.addCleanup(self.install.guard.close)
        target=self.install.root/'component'
        calls=[]
        def action():
            calls.append(1);target.write_text('verified')
        self.install.step('neovim',action,['component'])
        self.install.step('neovim',action,['component'])
        self.assertEqual(len(calls),1)
        target.write_text('damaged')
        self.install.step('neovim',action,['component'])
        self.assertEqual(len(calls),2)
        self.install.forced.add('neovim')
        self.install.step('neovim',action,['component'])
        self.assertEqual(len(calls),3)

    def test_cross_architecture_execution_is_rejected_before_writing(self):
        self.install.arch='aarch64' if module.platform.machine()=='x86_64' else 'x86_64'
        with self.assertRaisesRegex(module.InstallError,'cross-compile'):
            self.install.prepare()
        self.assertFalse(self.install.root.exists())

    def test_whitespace_build_prefix_is_rejected_before_downloading(self):
        args = argparse.Namespace(**vars(self.install.args))
        args.prefix = str(self.path/'build with spaces')
        other = module.Installer(args,self.lock)
        with self.assertRaisesRegex(module.InstallError,'without whitespace'):
            other.prepare()
        self.assertFalse(other.root.exists())

    def test_completed_install_keeps_user_configuration_after_move(self):
        import subprocess
        args = argparse.Namespace(**vars(self.install.args))
        args.prefix = str(self.path/'moved installation')
        other = module.Installer(args,self.lock)
        other.work.mkdir(parents=True)
        other.state['complete'] = True
        other.save()
        config = other.root/'env.sh'
        config.write_text('# user changes must survive\n')
        result = subprocess.run([sys.executable,str(SOURCE/'installer.py'),'--prefix',str(other.root)],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('already complete',result.stdout)
        self.assertEqual(config.read_text(),'# user changes must survive\n')

    def test_runtime_links_survive_relocation_without_build_tree(self):
        bindir = self.install.root/'opt/bin'
        bindir.mkdir(parents=True)
        target = bindir/'bzgrep'
        target.write_text('runtime')
        link = bindir/'bzfgrep'
        link.symlink_to(target)
        self.install.relocatable_links()
        self.assertEqual(os.readlink(link),'bzgrep')
        moved = self.path/'moved'
        self.install.root.rename(moved)
        self.assertEqual((moved/'opt/bin/bzfgrep').read_text(),'runtime')

    def test_runtime_links_to_host_or_build_tree_are_rejected(self):
        bindir = self.install.root/'opt/bin'
        bindir.mkdir(parents=True)
        for target in (self.path/'host-tool',self.install.work/'build/tool'):
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_text('not portable')
            link = bindir/'tool'
            link.symlink_to(target)
            with self.assertRaisesRegex(module.InstallError,'Non-portable'):
                self.install.relocatable_links()
            link.unlink()

    def test_rejected_version_does_not_replace_existing_state(self):
        import subprocess
        self.install.work.mkdir(parents=True)
        state=self.install.work/'state.json'
        text=json.dumps({'lock_sha256':'another release','architecture':module.platform.machine(),'steps':{'user':'preserve'}})
        state.write_text(text)
        result=subprocess.run([sys.executable,str(SOURCE/'installer.py'),'--prefix',str(self.install.root)],capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('same locked release',result.stderr)
        self.assertEqual(state.read_text(),text)

    def test_new_minimum_glibc_guard_and_relocation_environment(self):
        import shutil,subprocess
        root=self.path/'relocated path with spaces';root.mkdir()
        shutil.copy2(SOURCE/'overlay/env.sh',root/'env.sh')
        (root/'platform-architecture').write_text(module.platform.machine())
        (root/'minimum-glibc').write_text('999.0\n')
        result=subprocess.run(['bash','-c','source "$1/env.sh"','guard',str(root)],capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('999.0',result.stderr)
        (root/'minimum-glibc').write_text('2.34\n')
        result=subprocess.run(['bash','-c','before=$PATH; source "$1/env.sh" || exit; [[ "$ASTRONVIM_ROOT" == "$1" ]] || exit 2; astro_deactivate; [[ "$PATH" == "$before" ]]','guard',str(root)],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)


if __name__=='__main__':
    unittest.main(verbosity=2)
