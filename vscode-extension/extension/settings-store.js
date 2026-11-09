'use strict';
const fs=require('fs'),path=require('path'),os=require('os'),crypto=require('crypto');
const {KeyStore,parse}=require('./key-store');
const SETTING='terminal.integrated.rightClickBehavior',VALUE='nothing';
const SETTINGS=Object.freeze([{key:SETTING,value:VALUE},{key:'editor.multiCursorModifier',value:'ctrlCmd'}].map(Object.freeze));
const alive=pid=>{if(!Number.isSafeInteger(pid)||pid<=0)return false;try{process.kill(pid,0);return true}catch(error){return error.code==='EPERM'}};
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');

// Keep comments, indentation, unrelated values and user edits. JSONC validation
// belongs to the existing parser; this lexer only locates exact edit ranges.
function tokens(text){
  const out=[];let i=0;
  while(i<text.length){
    const start=i,c=text[i];
    if(/\s|\uFEFF/.test(c)){i++;continue}
    if(c==='/'&&text[i+1]==='/'){i+=2;while(i<text.length&&!/[\r\n]/.test(text[i]))i++;continue}
    if(c==='/'&&text[i+1]==='*'){const end=text.indexOf('*/',i+2);if(end<0)throw Error('Unterminated JSONC comment');i=end+2;continue}
    if(c==='"'){i++;while(i<text.length){if(text[i]==='\\'){i+=2;continue}if(text[i++]==='"')break}out.push({start,end:i,kind:'string',value:JSON.parse(text.slice(start,i))});continue}
    if('{}[]:,'.includes(c)){out.push({start,end:++i,kind:c});continue}
    while(i<text.length&&!/[\s{}\[\]:,\/]/.test(text[i]))i++;
    if(start===i)throw Error('Unexpected JSONC token');out.push({start,end:i,kind:'literal'});
  }
  return out;
}
function object(text){
  const decoded=parse(text);if(!decoded||Array.isArray(decoded)||typeof decoded!=='object')throw Error('Settings must contain a JSONC object');
  const ts=tokens(text),props=[];let i=1,previousComma=null;
  while(ts[i]&&ts[i].kind!=='}'){
    const name=ts[i++];if(name.kind!=='string'||ts[i++]?.kind!==':')throw Error('Invalid settings property');
    const first=ts[i],start=i;let depth=0;
    do{const t=ts[i++];if(t.kind==='{'||t.kind==='[')depth++;if(t.kind==='}'||t.kind===']')depth--}while(depth>0&&i<ts.length);
    const last=ts[i-1],followingComma=ts[i]?.kind===','?ts[i++]:null;
    props.push({key:name.value,start:name.start,end:last.end,valueStart:first.start,valueEnd:last.end,previousComma,followingComma});previousComma=followingComma;
    if(i===start)throw Error('Invalid settings property range');
  }
  if(ts[i]?.kind!=='}')throw Error('Unclosed settings object');
  return {decoded,props,close:ts[i].start};
}
function property(text,key){const obj=object(text),matches=obj.props.filter(p=>p.key===key);if(matches.length>1)throw Error('Duplicate managed settings key: '+key);return {obj,prop:matches[0]}}
function get(text,keys){
  const {prop}=property(text,keys[0]);if(!prop)return{present:false};
  const raw=text.slice(prop.valueStart,prop.valueEnd);if(keys.length===1)return{present:true,raw,value:parse(raw)};
  return get(raw,keys.slice(1));
}
function editProperty(text,key,raw){
  const {obj,prop}=property(text,key);
  if(prop){
    if(raw!==undefined)return text.slice(0,prop.valueStart)+raw+text.slice(prop.valueEnd);
    if(prop.followingComma)return text.slice(0,prop.start)+text.slice(prop.end,prop.followingComma.start)+text.slice(prop.followingComma.end);
    if(prop.previousComma)return text.slice(0,prop.previousComma.start)+text.slice(prop.previousComma.end,prop.start)+text.slice(prop.end);
    return text.slice(0,prop.start)+text.slice(prop.end);
  }
  if(raw===undefined)return text;
  const last=obj.props.at(-1),comma=last&&!last.followingComma?',':'';
  const newline=text.includes('\r\n')?'\r\n':'\n';
  return text.slice(0,obj.close)+comma+newline+'  '+JSON.stringify(key)+': '+raw+newline+text.slice(obj.close);
}
function edit(text,keys,raw){
  if(keys.length===1)return editProperty(text,keys[0],raw);
  const {prop}=property(text,keys[0]);
  if(!prop){if(raw===undefined)return text;let value=raw;for(let i=keys.length-1;i>0;i--)value='{'+JSON.stringify(keys[i])+':'+value+'}';return editProperty(text,keys[0],value)}
  const nested=text.slice(prop.valueStart,prop.valueEnd),changed=edit(nested,keys.slice(1),raw);
  return text.slice(0,prop.valueStart)+changed+text.slice(prop.valueEnd);
}
function checkPath(keys){if(!Array.isArray(keys)||!keys.length||keys.some(x=>typeof x!=='string'))throw Error('Invalid managed settings path')}
function entries(value=SETTINGS.map(s=>({keys:[s.key],value:s.value}))){
  if(Array.isArray(value)&&value.length&&value.every(x=>typeof x==='string'))value=[{keys:value,value:VALUE}];
  if(!Array.isArray(value)||!value.length)throw Error('Invalid managed settings entries');
  const seen=new Set();
  return value.map(entry=>{
    checkPath(entry.keys);const setting=SETTINGS.find(s=>s.key===entry.keys.at(-1));
    if(!setting||entry.value!==setting.value)throw Error('Unsupported managed setting');
    const id=JSON.stringify(entry.keys);if(seen.has(id))throw Error('Duplicate managed settings path');seen.add(id);
    return{keys:[...entry.keys],value:entry.value};
  }).sort((a,b)=>JSON.stringify(a.keys).localeCompare(JSON.stringify(b.keys)));
}
function stateEntries(state){
  const values=state.settings||[{keys:state.setting_path||[SETTING],value:VALUE,original:state.original,user_override:state.user_override}];
  const checked=entries(values);
  return checked.map(entry=>{
    const source=values.find(s=>JSON.stringify(s.keys)===JSON.stringify(entry.keys));
    if(!source.original||typeof source.original.present!=='boolean')throw Error('Invalid managed setting original');
    return{...entry,original:source.original,...(source.user_override?{user_override:true}:{}),...(source.released?{released:true}:{})};
  });
}

class SettingsStore extends KeyStore{
  constructor(home=os.homedir(),owner,options={}){
    super(SETTINGS,home,owner,options);
    this.legacyRoot=path.join(home,'.astronvim','vscode-settings-backups');
    this.root=path.join(home,'.astronvim','vscode-settings-backups-v3');this.lockRoot=this.legacyRoot;
    this.leaseDir=path.join(this.root,'leases');this.userOverrides=new Set();this.legacyRecovered=false;
    this.registrationPlans=new Map();
  }
  // The 1.0.7 reader understands one setting only. Keep every v3 transaction
  // outside its registrations; share its lock and publish only a live protocol
  // guard in its lease directory. Never fabricate a pid or a permanent guard.
  assertNoLegacy(){
    super.assertNoLegacy();
    const dir=path.join(this.legacyRoot,'leases');if(!fs.existsSync(dir))return;
    for(const name of fs.readdirSync(dir)){
      const file=path.join(dir,name);let row;try{row=JSON.parse(fs.readFileSync(file,'utf8'))}catch(error){if(error.code==='ENOENT')continue;throw error}
      if(!alive(row.pid)){fs.unlinkSync(file);continue}
      if(row.schema===3&&row.settings_protocol===3)continue;
      const error=Error('An older AstroNvim settings client is active. Close its VS Code windows before enabling 1.0.8 mouse routing. Existing preferences were not changed.');error.code='ASTRO_LEGACY_CLIENT';throw error;
    }
  }
  recoverLegacyLocked(){
    if(this.legacyRecovered)return;
    if(fs.existsSync(this.legacyRoot))for(const name of fs.readdirSync(this.legacyRoot)){
      if(!/^[a-f0-9]{20}$/.test(name))continue;
      const dir=path.join(this.legacyRoot,name);
      if(!fs.existsSync(path.join(dir,'profile.json'))&&!fs.existsSync(path.join(dir,'registration.json')))continue;
      if(this.profileLeases(dir).length){const error=Error('An older AstroNvim settings Profile is still leased. Close its VS Code window before upgrading.');error.code='ASTRO_LEGACY_CLIENT';throw error}
      this.recover(dir);
      const pending=path.join(dir,'pending.json');
      if(fs.existsSync(pending)){
        const state=JSON.parse(fs.readFileSync(pending,'utf8')),current=this.publicationTarget(state.target);
        if(!((current&&hash(current)===state.previous_sha256)||(!current&&state.previous_existed===false)))throw Error('Unresolved legacy settings publication; recovery stopped');
        // Otherwise a second v3 owner could mistake our later `nothing` value
        // for publication of this old, never-published single-key intent.
        fs.renameSync(pending,path.join(dir,'canceled-unpublished-'+Date.now()+'-'+this.owner+'-'+(++this.counter)+'.json'));
      }
      this.restore(dir);
    }
    this.legacyRecovered=true;
  }
  acquireLocked(){
    this.assertNoLegacy();this.recoverLegacyLocked();
    const guard=path.join(this.legacyRoot,'leases',this.owner+'.json');
    if(!fs.existsSync(guard))this.atomic(guard,JSON.stringify({schema:3,settings_protocol:3,pid:process.pid,owner:this.owner,version:this.version}));
    return super.acquireLocked();
  }
  releaseLocked(options={}){
    this.assertNoLegacy();this.recoverLegacyLocked();
    const done=super.releaseLocked(options);
    // KeyStore keeps a whole-file lease. Settings release only those keys that
    // no remaining window requests; other owners retain their own subset.
    if(!done)for(const dir of options.all?this.registrations():this.targets.keys())if(this.profileLeases(dir).length){this.recover(dir);this.restore(dir)}
    try{fs.unlinkSync(path.join(this.legacyRoot,'leases',this.owner+'.json'))}catch(error){if(error.code!=='ENOENT')throw error}
    this.legacyRecovered=false; // A 107 client may enter after this guard leaves.
    return done;
  }
  register(target,managed){
    const settings=entries(managed);target=path.resolve(target);
    const identity=process.platform==='win32'?target.toLowerCase():target;
    const dir=path.join(this.root,hash(identity).slice(0,20)),file=path.join(dir,'profile.json');
    // Publish the path in the same atomic metadata write. Calling the base
    // register first would expose a transient top-level path to another window.
    const bytes=JSON.stringify({target,schema:3,settings});
    if(!fs.existsSync(file)||fs.readFileSync(file,'utf8')!==bytes)this.atomic(file,bytes);
    this.targets.set(dir,target);this.registrationPlans.set(dir,settings);return dir;
  }
  settings(dir){
    if(this.registrationPlans.has(dir))return this.registrationPlans.get(dir);
    const profile=JSON.parse(fs.readFileSync(path.join(dir,'profile.json'),'utf8'));
    return entries(profile.settings||profile.setting_path||[SETTING]);
  }
  profileLeaseMetadata(dir){return{settings:this.settings(dir)}}
  requestedSettings(dir,includeOwn=false){
    const union=new Map(),rows=this.profileLeases(dir,includeOwn?this.owner:undefined);
    for(const row of rows){
      // A pre-update v3 lease without key metadata conservatively retains the
      // active transaction's keys until that owner leaves.
      const state=row.settings?null:this.publicationState(path.join(dir,'active.json'));
      const managed=row.settings?entries(row.settings):state?stateEntries(state).filter(s=>!s.released):[];
      for(const setting of managed)union.set(JSON.stringify(setting.keys),{keys:setting.keys,value:setting.value});
    }
    if(includeOwn)for(const setting of this.settings(dir))union.set(JSON.stringify(setting.keys),setting);
    return union.size?entries([...union.values()]):[];
  }
  publicationError(error,operation,dir,target,before,existed,state){
    // Only the already validated settings target's own atomic replacement can
    // be deferred. Metadata/backup/cleanup errors retain their original path.
    const same=(a,b)=>typeof a==='string'&&path.resolve(a).toLowerCase()===path.resolve(b).toLowerCase();
    if(process.platform!=='win32'||error.code!=='EPERM'||error.syscall!=='rename'||!same(error.dest,target)
      ||typeof error.path!=='string'||!error.path.toLowerCase().startsWith((target+'.astro-tmp-'+this.owner+'-').toLowerCase())
      ||this.targets.get(dir)!==target)return error;
    const context=Object.freeze({operation,dir,target,owner:this.owner,existed,before:before.toString('base64'),
      stateIdentity:hash(JSON.stringify(state)),backup:state.backup,installed:state.installed_sha256,
      publicationId:state.publication_id,
      settings:Object.freeze(stateEntries(state).map(s=>Object.freeze({keys:Object.freeze([...s.keys]),value:s.value})))});
    if(!this.publicationContexts)this.publicationContexts=new WeakSet();
    this.publicationContexts.add(context);error.astroPublication=context;return error;
  }
  checkPublication(context,operation){
    if(!this.publicationContexts||!this.publicationContexts.has(context)||context.owner!==this.owner||context.operation!==operation
      ||this.targets.get(context.dir)!==context.target)throw Error('Settings publication context does not belong to this Store');
  }
  publicationState(file){try{return JSON.parse(fs.readFileSync(file,'utf8'))}catch(error){if(error.code==='ENOENT')return null;throw error}}
  publicationTarget(target){try{return fs.readFileSync(target)}catch(error){if(error.code==='ENOENT')return null;throw error}}
  publicationCommitted(context){
    const active=this.publicationState(path.join(context.dir,'active.json'));
    return Boolean(active&&active.target===context.target&&(
      context.publicationId&&active.publication_ids?.includes(context.publicationId)
      ||active.backup===context.backup&&active.installed_sha256===context.installed));
  }
  cancelAcquireLocked(context){
    const file=path.join(context.dir,'pending.json'),pending=this.publicationState(file);
    // The first rename was known to fail. Delete only this exact uncommitted
    // intent before release/recover can mistake a user's new `nothing` value
    // for a crash after publication. Other owners' active state is untouched.
    if(pending&&hash(JSON.stringify(pending))===context.stateIdentity&&!this.publicationCommitted(context))fs.unlinkSync(file);
    return this.releaseLocked({});
  }
  cancelAcquire(context){this.checkPublication(context,'acquire');return this.locked(()=>this.cancelAcquireLocked(context))}
  resumeAcquire(context){
    this.checkPublication(context,'acquire');
    return this.locked(()=>{
      const current=this.publicationTarget(context.target),unchanged=context.existed
        ?current!==null&&current.toString('base64')===context.before:current===null;
      if(!unchanged&&!this.publicationCommitted(context)){
        this.cancelAcquireLocked(context);this.userOverrides.add(context.target);
        return{status:'canceled',reason:'user_edit'};
      }
      this.acquireLocked();
      if(this.userOverrides.has(context.target)){this.releaseLocked({});return{status:'canceled',reason:'user_edit'}}
      return{status:'committed'};
    });
  }
  resumeRestore(context){this.checkPublication(context,'restore');return this.locked(()=>this.releaseLocked({}))}
  recover(dir){
    const pending=path.join(dir,'pending.json');if(!fs.existsSync(pending))return;
    const state=JSON.parse(fs.readFileSync(pending,'utf8')),current=fs.existsSync(state.target)?fs.readFileSync(state.target):null;
    if((current&&hash(current)===state.previous_sha256)||(!current&&state.previous_existed===false))return;
    // A later user edit may change one managed key. Recover ownership of the
    // other published keys so their temporary values can still be restored.
    if(current&&(hash(current)===state.installed_sha256||(state.publication_changes?state.publication_changes.some(s=>{const value=get(current.toString('utf8'),s.keys);return value.present===s.after.present&&JSON.stringify(value.value)===JSON.stringify(s.after.value)}):stateEntries(state).some(s=>get(current.toString('utf8'),s.keys).value===s.value))))this.atomic(path.join(dir,'active.json'),JSON.stringify(state,null,2));
    fs.unlinkSync(pending);
  }
  prepareEnable(dir,target){return this.prepareSettings(dir,target,this.requestedSettings(dir,true),true)}
  prepareSettings(dir,target,managed,acquiring=false){
    const existed=fs.existsSync(target),raw=existed?fs.readFileSync(target):Buffer.from('{}\n'),text=raw.toString('utf8');
    const stateFile=path.join(dir,'active.json');let state=this.publicationState(stateFile);
    const previous=state?stateEntries(state):[],wanted=new Map(managed.map(s=>[JSON.stringify(s.keys),s]));
    const observed=previous.map(s=>({...s,...(!s.released&&get(text,s.keys).value!==s.value?{user_override:true}:{})}));
    if(acquiring&&observed.some(s=>!s.released&&s.user_override&&this.settings(dir).some(own=>JSON.stringify(own.keys)===JSON.stringify(s.keys)))){
      if(JSON.stringify(observed)!==JSON.stringify(previous)){
        state={...state,schema:3,settings:observed};delete state.setting_path;delete state.original;delete state.user_override;
        this.atomic(stateFile,JSON.stringify(state,null,2));
      }
      this.userOverrides.add(target);return null;
    }
    if(acquiring)this.userOverrides.delete(target);
    const byKey=new Map(observed.map(s=>[JSON.stringify(s.keys),s]));let changed=text;
    for(const setting of observed)if(!wanted.has(JSON.stringify(setting.keys))&&!setting.released){
      if(!setting.user_override&&get(changed,setting.keys).value===setting.value)changed=edit(changed,setting.keys,setting.original.present?setting.original.raw:undefined);
      setting.released=true;
    }
    for(const managedSetting of managed){
      const id=JSON.stringify(managedSetting.keys);let setting=byKey.get(id);
      if(!setting||setting.released){setting={...managedSetting,original:get(changed,managedSetting.keys)};byKey.set(id,setting)}
      if(!setting.user_override)changed=edit(changed,setting.keys,JSON.stringify(setting.value));
    }
    const settings=[...byKey.values()].sort((a,b)=>JSON.stringify(a.keys).localeCompare(JSON.stringify(b.keys)));
    const bytes=Buffer.from(changed);parse(changed);
    if(state&&bytes.equals(raw)&&JSON.stringify(settings)===JSON.stringify(previous))return null;
    const pending=path.join(dir,'pending.json'),next=this.publicationState(pending);
    return{existed,raw,settings,state,stateFile,bytes,pending,next};
  }
  enable(dir,target=this.target(dir),prepared){
    if(prepared===undefined)prepared=this.prepareEnable(dir,target);if(prepared===null)return;
    return this.publishSettings(dir,target,prepared,'acquire');
  }
  publishSettings(dir,target,prepared,operation){
    const{existed,raw,settings,state,stateFile,bytes,pending}=prepared;let{next}=prepared;
    if(!next||next.target!==target||next.previous_existed!==existed||next.previous_sha256!==hash(raw)||next.installed_sha256!==hash(bytes)||next.bindings_sha256!==this.bindingsHash||JSON.stringify(next.settings)!==JSON.stringify(settings)){
      const tag=Date.now()+'-'+this.owner+'-'+(++this.counter),backup=state?state.backup:'baseline-'+tag+'.json';
      if(!state)this.atomic(path.join(dir,backup),raw);
      const before=raw.toString('utf8'),after=bytes.toString('utf8'),changes=[];
      for(const setting of settings){
        const old=get(before,setting.keys),value=get(after,setting.keys);
        if(old.present!==value.present||JSON.stringify(old.value)!==JSON.stringify(value.value))changes.push({keys:setting.keys,before:old,after:value});
      }
      // A different owner may publish a larger union while this owner awaits
      // an EPERM retry. Preserve those intents so the waiter recognizes the
      // extension's committed successor instead of treating it as a user edit.
      const publicationIds=[...new Set([...(state?.publication_ids||[]),...(next?.publication_ids||[]),tag])];
      next={schema:3,target,backup,existed:state?state.existed:existed,previous_existed:existed,previous_sha256:hash(raw),installed_sha256:hash(bytes),bindings_sha256:this.bindingsHash,version:this.version,settings,publication_id:tag,publication_ids:publicationIds,
        exact_restore:state?state.exact_restore!==false&&hash(raw)===state.installed_sha256:true,publication_changes:changes};
      this.atomic(pending,JSON.stringify(next,null,2));
    }
    if(fs.existsSync(target)!==existed||(existed&&!fs.readFileSync(target).equals(raw))){fs.unlinkSync(pending);throw Error('Settings changed concurrently')}
    if(!existed||!bytes.equals(raw))try{this.atomic(target,bytes)}catch(error){throw this.publicationError(error,operation,dir,target,raw,existed,next)}
    this.atomic(stateFile,JSON.stringify(next,null,2));fs.unlinkSync(pending);
  }
  restore(dir){
    const file=path.join(dir,'active.json');if(!fs.existsSync(file))return;
    const state=JSON.parse(fs.readFileSync(file,'utf8')),settings=stateEntries(state),remaining=this.requestedSettings(dir);
    if(remaining.length){
      if(!fs.existsSync(state.target))return;
      const prepared=this.prepareSettings(dir,state.target,remaining);
      if(prepared)this.publishSettings(dir,state.target,prepared,'restore');
      return;
    }
    if(fs.existsSync(state.target)){
      const current=fs.readFileSync(state.target),text=current.toString('utf8');
      if(state.exact_restore!==false&&!settings.some(s=>s.user_override)&&hash(current)===state.installed_sha256){
        const original=state.existed?fs.readFileSync(path.join(dir,path.basename(state.backup))):null;
        if(!fs.existsSync(state.target)||!fs.readFileSync(state.target).equals(current))throw Error('Settings changed concurrently during restore');
        if(state.existed){if(!original.equals(current))try{this.atomic(state.target,original)}catch(error){throw this.publicationError(error,'restore',dir,state.target,current,true,state)}}else fs.unlinkSync(state.target);
      }
      else{
        let changed=text;
        for(const setting of settings)if(!setting.released&&!setting.user_override&&get(changed,setting.keys).value===setting.value)changed=edit(changed,setting.keys,setting.original.present?setting.original.raw:undefined);
        const restored=Buffer.from(changed);parse(changed);
        if(!fs.readFileSync(state.target).equals(current))throw Error('Settings changed concurrently during restore');
        if(!restored.equals(current))try{this.atomic(state.target,restored)}catch(error){throw this.publicationError(error,'restore',dir,state.target,current,true,state)}
      }
      // Otherwise an explicit user change wins, even if there was no poll yet.
    }
    const pending=path.join(dir,'pending.json');
    if(fs.existsSync(pending))fs.renameSync(pending,path.join(dir,'canceled-restored-'+Date.now()+'-'+this.owner+'-'+(++this.counter)+'.json'));
    fs.renameSync(file,path.join(dir,'restored-'+Date.now()+'-'+this.owner+'-'+(++this.counter)+'.json'));this.userOverrides.delete(state.target);
  }
}
module.exports={SettingsStore,SETTING,VALUE,SETTINGS,get,edit,object};
