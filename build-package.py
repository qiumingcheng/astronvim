#!/usr/bin/env python3
"""Package only first-party source, incremental patches and documentation."""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parent
ALLOWED_TOP = {'install.sh', 'installer.py', 'recipes.py', 'build-package.py', 'README.md', 'AGENTS.md',
               'dependencies.lock.json', 'plugins.lock.json', 'parsers.lock.json', 'patches.lock.json',
               'source-files.json', 'VALIDATION.md'}
ALLOWED_DIRS = {'overlay', 'patches', 'tests', 'vscode-extension'}
BAD_SUFFIX = {'.pyc','.pyo','.so','.a','.o','.vsix','.gz','.xz','.zip','.log'}


def main():
    if not (ROOT/'VALIDATION.md').is_file():
        raise SystemExit('VALIDATION.md is required; record the tested and untested scope before packaging')
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',required=True)
    args=parser.parse_args()
    output=Path(args.output).expanduser().resolve()
    if output.exists():
        raise SystemExit('Output already exists: '+str(output))
    if ROOT in output.parents:
        raise SystemExit('Keep output outside the source directory')
    paths=[]
    for path in sorted(ROOT.rglob('*')):
        relative=path.relative_to(ROOT)
        if '__pycache__' in relative.parts or path.is_dir():
            continue
        if len(relative.parts)==1 and relative.name not in ALLOWED_TOP:
            raise SystemExit('Unexpected source root file: '+str(relative))
        if len(relative.parts)>1 and relative.parts[0] not in ALLOWED_DIRS:
            raise SystemExit('Unexpected source directory: '+str(relative))
        if path.is_symlink() or path.suffix in BAD_SUFFIX or path.read_bytes()[:4] == b'\x7fELF':
            raise SystemExit('Non-source artifact rejected: '+str(relative))
        if relative.name!='source-files.json':
            paths.append(path)
    hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    manifest=ROOT/'source-files.json'
    manifest.write_text(json.dumps(hashes,ensure_ascii=False,indent=2)+'\n')
    paths.append(manifest)
    output.parent.mkdir(parents=True,exist_ok=True)
    temporary=output.with_name(output.name+'.partial')
    with temporary.open('xb') as raw, gzip.GzipFile(filename='',mode='wb',fileobj=raw,mtime=0,compresslevel=6) as gz:
        with tarfile.open(fileobj=gz,mode='w') as tar:
            for path in sorted(paths):
                info=tar.gettarinfo(str(path),arcname='astronvim-source/'+str(path.relative_to(ROOT)))
                info.uid=info.gid=0;info.uname=info.gname='';info.mtime=0
                with path.open('rb') as content:
                    tar.addfile(info,content)
    # Refuse a competing publisher instead of replacing an existing delivery.
    import os
    os.link(temporary,output)
    temporary.unlink()
    checksum=hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_name(output.name+'.sha256').write_text(checksum+'  '+output.name+'\n')
    print(json.dumps({'archive':str(output),'bytes':output.stat().st_size,'files':len(paths),'sha256':checksum},ensure_ascii=False))


if __name__=='__main__':
    main()
