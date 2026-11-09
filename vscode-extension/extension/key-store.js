'use strict';
const fs=require('fs'),path=require('path'),os=require('os'),crypto=require('crypto');
const BEGIN='// BEGIN AstroNvim portable terminal keys',END='// END AstroNvim portable terminal keys';
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const significant=s=>s.replace(/"(?:\\.|[^"\\])*"|\/\/[^\r\n]*|\/\*[\s\S]*?\*\//g,m=>m[0]==='"'?m:m.replace(/[^\n]/g,' '));
function parse(s){return JSON.parse(significant(s.replace(/^\uFEFF/,'' )).replace(/"(?:\\.|[^"\\])*"|,(?=\s*[}\]])/g,m=>m[0]==='"'?m:' '))}
function strip(s){
  if(!s.includes(BEGIN))return s;
  const start=s.indexOf(BEGIN),end=s.indexOf(END,start);
  if(end<0||s.indexOf(BEGIN,start+1)>=0)throw Error('Malformed AstroNvim shortcut block');
  let a=s.slice(0,start),b=s.slice(end+END.length);
  const left=significant(a).trimEnd(),right=significant(b).trimStart();
  if(left.endsWith(',')&&right.startsWith(']'))a=a.slice(0,left.length-1)+a.slice(left.length);
  else if((left.endsWith('[')||left.endsWith(','))&&right.startsWith(',')){
    const i=b.length-right.length;b=b.slice(0,i)+b.slice(i+1);
  }
  const ret=a+b;parse(ret);return ret;
}
function merge(s,bindings){
  s=strip(s);if(!Array.isArray(parse(s)))throw Error('keybindings.json must contain an array');
  const clean=significant(s),end=clean.trimEnd().length-1;
  const comma='[,'.includes(clean.slice(0,end).trimEnd().slice(-1))?'':',';
  const serialized=JSON.stringify(bindings,null,2);
  const block=serialized.slice(2,-2);
  const out=s.slice(0,end)+comma+'\n'+BEGIN+'\n'+block+'\n'+END+'\n'+s.slice(end);
  // A validated JSONC array plus a JSON-serialized array fragment remains an
  // array. Keep the historical check for unsupported/exotic caller values.
  if(!Array.isArray(bindings)||serialized[0]!=='[')parse(out);
  return out;
}
const PACKAGE_VERSION=require('./package.json').version;
const stamp=file=>{try{const s=fs.statSync(file);return [s.ino,s.size,s.mtimeMs,s.ctimeMs].join(':')}catch(e){if(e.code==='ENOENT')return '-';throw e}};
function alive(pid){if(!Number.isSafeInteger(pid)||pid<=0)return false;try{process.kill(pid,0);return true}catch(e){return e.code==='EPERM'}}
function compareVersion(a,b){const x=String(a).split('.').map(Number),y=String(b).split('.').map(Number);for(let i=0;i<3;i++){const d=(x[i]||0)-(y[i]||0);if(d)return d}return 0}
class KeyStore{
  constructor(bindings,home=os.homedir(),owner=String(process.pid)+'-'+crypto.randomBytes(6).toString('hex'),options={}){
    this.root=path.join(home,'.astronvim','vscode-backups');this.bindings=bindings;this.owner=owner;
    this.bindingsHash=hash(JSON.stringify(bindings));this.version=options.version||PACKAGE_VERSION;
    this.leaseDir=path.join(this.root,'leases');this.targets=new Map();this.lastLease=0;
    this.snapshots=new Map();this.counter=0;this.releaseStamp=null;this.lastRelease=0;
  }
  registrations(){
    if(!fs.existsSync(this.root))return [];
    return fs.readdirSync(this.root).filter(n=>/^[a-f0-9]{20}$/.test(n)).map(n=>path.join(this.root,n))
      .filter(d=>fs.existsSync(path.join(d,'profile.json'))||fs.existsSync(path.join(d,'registration.json')));
  }
  register(target){
    target=path.resolve(target);
    const id=process.platform==='win32'?target.toLowerCase():target;
    const dir=path.join(this.root,hash(id).slice(0,20));
    // New registrations are invisible to old clients that scan registration.json.
    const metadata=path.join(dir,'profile.json'),bytes=JSON.stringify({target,schema:2});
    if(!fs.existsSync(metadata)||fs.readFileSync(metadata,'utf8')!==bytes)this.atomic(metadata,bytes);
    this.targets.set(dir,target);return dir;
  }
  target(dir){
    const metadata=fs.existsSync(path.join(dir,'profile.json'))?'profile.json':'registration.json';
    return JSON.parse(fs.readFileSync(path.join(dir,metadata),'utf8')).target;
  }
  locked(action){
    const lockRoot=this.lockRoot||this.root;fs.mkdirSync(lockRoot,{recursive:true,mode:0o700});const lock=path.join(lockRoot,'update.lock');
    try{fs.mkdirSync(lock)}catch(error){
      if(error.code!=='EEXIST')throw error;
      let live=true;
      try{const pid=Number(fs.readFileSync(path.join(lock,'pid'),'utf8'));live=alive(pid)}
      catch(e){live=!(e.code==='ENOENT'&&Date.now()-fs.statSync(lock).mtimeMs>10000)}
      if(live){const error=Error('Shortcut backup is busy; retrying');error.code='ASTRO_LOCK_BUSY';throw error}
      fs.rmSync(lock,{recursive:true});fs.mkdirSync(lock);
    }
    try{fs.writeFileSync(path.join(lock,'pid'),String(process.pid));return action()}
    finally{fs.rmSync(lock,{recursive:true,force:true})}
  }
  atomic(file,bytes){
    fs.mkdirSync(path.dirname(file),{recursive:true});const tmp=file+'.astro-tmp-'+this.owner+'-'+(++this.counter);
    try{fs.writeFileSync(tmp,bytes,{mode:0o600});fs.renameSync(tmp,file)}
    catch(error){try{fs.unlinkSync(tmp)}catch(cleanup){if(cleanup.code!=='ENOENT')throw cleanup}throw error}
  }
  legacyClients(){
    const found=[];if(!fs.existsSync(this.leaseDir))return found;
    for(const name of fs.readdirSync(this.leaseDir)){
      const file=path.join(this.leaseDir,name);let row;
      try{row=JSON.parse(fs.readFileSync(file,'utf8'))}catch{continue}
      if(alive(row.pid)&&row.schema!==2)found.push(row.pid);
      else if(!alive(row.pid))try{fs.unlinkSync(file)}catch{}
    }
    return found;
  }
  assertNoLegacy(){
    const legacy=this.legacyClients();
    if(legacy.length){const error=Error('An older AstroNvim keyboard extension is still running. Reload or close its VS Code windows before enabling version '+this.version+'. Existing shortcuts were not changed.');error.code='ASTRO_LEGACY_CLIENT';throw error}
  }
  profileLeases(dir,replaceOwner){
    const leases=path.join(dir,'leases'),rows=[];if(!fs.existsSync(leases))return rows;
    for(const name of fs.readdirSync(leases)){
      if(replaceOwner!==undefined&&name===replaceOwner+'.json')continue;
      const file=path.join(leases,name);let row;
      try{row=JSON.parse(fs.readFileSync(file,'utf8'))}catch{continue}
      if(row.schema===2&&alive(row.pid))rows.push(row);
      else if(row.schema===2)try{fs.unlinkSync(file)}catch{}
    }
    return rows;
  }
  snapshot(dir,target){return [stamp(target),stamp(path.join(dir,'active.json')),stamp(path.join(dir,'pending.json')),stamp(path.join(dir,'leases')),stamp(this.leaseDir)].join('|')}
  acquire(){
    this.releaseStamp=null;
    const heartbeat=Date.now()-this.lastLease>=5000;
    let changed=heartbeat||this.snapshots.size!==this.targets.size;
    if(!changed)for(const [dir,target] of this.targets)if(this.snapshots.get(dir)!==this.snapshot(dir,target)){changed=true;break}
    if(!changed)return true;
    return this.locked(()=>this.acquireLocked());
  }
  willOwnProfile(dir,target,row){
    const rows=this.profileLeases(dir,this.owner);rows.push({...row,target});
    rows.sort((a,b)=>compareVersion(b.version,a.version)||b.bindings_sha256.localeCompare(a.bindings_sha256));
    const winner=rows[0];return Boolean(winner&&winner.version===this.version&&winner.bindings_sha256===this.bindingsHash);
  }
  acquireLocked(){
    this.assertNoLegacy();
    const now=Date.now(),row={schema:2,pid:process.pid,owner:this.owner,time:now,version:this.version,bindings_sha256:this.bindingsHash};
    const renew=now-this.lastLease>=5000,first=renew&&this.lastLease===0?this.targets.entries().next().value:undefined;
    // Validate the current Profile before publishing ownership. Predict exactly
    // the lease that this locked transaction will write; never parse a loser's target.
    let firstOwned=false,prepared;
    if(first&&this.willOwnProfile(first[0],first[1],row)){
      firstOwned=true;this.recover(first[0]);prepared=this.prepareEnable(first[0],first[1]);
    }
    if(renew){
      this.atomic(path.join(this.leaseDir,this.owner+'.json'),JSON.stringify(row));
      for(const [dir,target] of this.targets)this.atomic(path.join(dir,'leases',this.owner+'.json'),JSON.stringify({...row,target,...(this.profileLeaseMetadata?this.profileLeaseMetadata(dir,target):{})}));
      this.lastLease=now;
    }
    for(const [dir,target] of this.targets){
      if(first&&dir===first[0]){if(firstOwned)this.enable(dir,target,prepared===null?undefined:prepared);prepared=undefined;firstOwned=false}
      else{
        // Other Profiles retain the original lease/recover/publish order.
        const rows=this.profileLeases(dir).sort((a,b)=>compareVersion(b.version,a.version)||b.bindings_sha256.localeCompare(a.bindings_sha256));
        const winner=rows[0];
        if(winner&&winner.version===this.version&&winner.bindings_sha256===this.bindingsHash){this.recover(dir);this.enable(dir,target)}
      }
      this.snapshots.set(dir,this.snapshot(dir,target));
    }
    return true;
  }

  recover(dir){
    const pending=path.join(dir,'pending.json');if(!fs.existsSync(pending))return;
    const state=JSON.parse(fs.readFileSync(pending,'utf8'));
    const current=fs.existsSync(state.target)?fs.readFileSync(state.target):null;
    // Publication never happened: retain the transaction and its backups so
    // each prompt retry does not create another pair of identical files.
    if((current&&hash(current)===state.previous_sha256)||(!current&&state.previous_existed===false))return;
    if(current&&hash(current)===state.installed_sha256)this.atomic(path.join(dir,'active.json'),JSON.stringify(state,null,2));
    else if(current&&current.toString('utf8').includes(BEGIN)&&state.previous_sha256!==hash(current)){
      // A user may edit after target publication but before the state commit.
      // Keep the pending restore baseline; restore() will preserve that edit.
      parse(current.toString('utf8'));this.atomic(path.join(dir,'active.json'),JSON.stringify(state,null,2));
    }
    fs.unlinkSync(pending);
  }
  prepareEnable(dir,target){
    const existed=fs.existsSync(target),raw=existed?fs.readFileSync(target):Buffer.from('[]\n');
    const stateFile=path.join(dir,'active.json');
    const state=fs.existsSync(stateFile)?JSON.parse(fs.readFileSync(stateFile,'utf8')):null;
    const unchanged=Boolean(state&&hash(raw)===state.installed_sha256);
    if(unchanged&&state.bindings_sha256===this.bindingsHash)return null;
    const pending=path.join(dir,'pending.json');
    const next=fs.existsSync(pending)?JSON.parse(fs.readFileSync(pending,'utf8')):null;
    const bytes=Buffer.from(merge(raw.toString('utf8'),this.bindings));
    return {existed,raw,stateFile,state,unchanged,pending,next,bytes};
  }
  enable(dir,target=this.target(dir),prepared){
    if(prepared===undefined)prepared=this.prepareEnable(dir,target);
    if(prepared===null)return;
    const {existed,raw,stateFile,state,unchanged,pending,bytes}=prepared;
    let {next}=prepared;
    const reusable=next&&next.target===target&&next.previous_existed===existed
      &&next.previous_sha256===hash(raw)&&next.bindings_sha256===this.bindingsHash
      &&next.installed_sha256===hash(bytes);
    if(!reusable){
      const baseline=unchanged?fs.readFileSync(path.join(dir,path.basename(state.backup))):Buffer.from(strip(raw.toString('utf8')));
      const baselineExisted=unchanged?state.existed:existed;
      const tag=Date.now()+'-'+this.owner+'-'+(++this.counter),backup='baseline-'+tag+'.json';
      this.atomic(path.join(dir,'before-'+tag+'.json'),raw);this.atomic(path.join(dir,backup),baseline);
      next={schema:2,target,backup,existed:baselineExisted,previous_existed:existed,previous_sha256:hash(raw),installed_sha256:hash(bytes),bindings_sha256:this.bindingsHash,version:this.version};
      this.atomic(pending,JSON.stringify(next,null,2));
    }
    if(fs.existsSync(target)!==existed||(existed&&!fs.readFileSync(target).equals(raw))){fs.unlinkSync(pending);throw Error('Shortcuts changed concurrently')}
    this.atomic(target,bytes);this.atomic(stateFile,JSON.stringify(next,null,2));fs.unlinkSync(pending);
  }
  release(options={}){
    if(!options.all&&this.releaseStamp!==null&&Date.now()-this.lastRelease<1000){
      const signature=Array.from(this.targets,([dir,target])=>this.snapshot(dir,target)).join(';');
      if(this.releaseStamp===signature)return false;
    }else{
      // A full cache signature cannot match here. Still validate target paths:
      // restore's existsSync must not disguise EACCES/ENOTDIR as a missing file.
      for(const [,target] of this.targets)stamp(target);
    }
    const result=this.locked(()=>this.releaseLocked(options));
    this.releaseStamp=result?null:Array.from(this.targets,([dir,target])=>this.snapshot(dir,target)).join(';');
    this.lastRelease=Date.now();return result;
  }
  releaseLocked(options={}){
    this.snapshots.clear();this.lastLease=0;
    for(const [dir] of this.targets)try{fs.unlinkSync(path.join(dir,'leases',this.owner+'.json'))}catch(e){if(e.code!=='ENOENT')throw e}
    try{fs.unlinkSync(path.join(this.leaseDir,this.owner+'.json'))}catch(e){if(e.code!=='ENOENT')throw e}
    // 1.0.1 and older clients restore every registered profile. Do not race
    // their protocol; let the user reload the old windows before migration.
    this.assertNoLegacy();
    const dirs=options.all?this.registrations():Array.from(this.targets.keys());
    let waiting=false;
    for(const dir of dirs){if(this.profileLeases(dir).length){waiting=true;continue}this.recover(dir);this.restore(dir)}
    return !waiting;
  }
  restore(dir){
    const file=path.join(dir,'active.json');if(!fs.existsSync(file))return;
    const s=JSON.parse(fs.readFileSync(file,'utf8')),baseline=fs.readFileSync(path.join(dir,path.basename(s.backup)));
    if(fs.existsSync(s.target)){
      const current=fs.readFileSync(s.target);
      if(hash(current)===s.installed_sha256){if(s.existed)this.atomic(s.target,baseline);else fs.unlinkSync(s.target)}
      else if(current.toString('utf8').includes(BEGIN))this.atomic(s.target,strip(current.toString('utf8')));
    }
    fs.renameSync(file,path.join(dir,'restored-'+Date.now()+'-'+this.owner+'-'+(++this.counter)+'.json'));
  }
}
module.exports={KeyStore,parse,strip,merge};
