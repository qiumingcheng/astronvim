'use strict';
const path=require('path');
const {SettingsStore,SETTING,VALUE,SETTINGS}=require('./settings-store');

// A WINDOW setting has no per-terminal stable API. Hold the profile/workspace
// lease only while this window's active terminal is AstroNvim; other windows
// using the same settings file retain their independent leases.
class MouseController{
  constructor(vscode,profileSettings,log,options={}){
    this.vscode=vscode;this.profileSettings=profileSettings;this.log=log;this.Store=options.Store||SettingsStore;
    this.store=new this.Store();this.registered=false;this.planKey=JSON.stringify([[path.resolve(profileSettings),SETTINGS.map(x=>({keys:[x.key],value:x.value}))]]);
    this.hasLease=false;this.needsRestore=true;this.initialRecovery=true;this.lastSync=0;this.lastReleaseAttempt=0;this.suppressed=new Set();this.lastError='';this.dirty=true;
    this.pending=null;this.failed=null;this.cancelRequired=null;this.transitionIntent=undefined;this.activeToken=null;this.generation=0;this.publicationCounter=0;this.disposed=false;
    this.change=typeof vscode.workspace.onDidChangeConfiguration==='function'?vscode.workspace.onDidChangeConfiguration(e=>{if(SETTINGS.some(x=>e.affectsConfiguration(x.key)))this.dirty=true}):null;
  }
  error(error){const message=String(error);if(message!==this.lastError){this.lastError=message;this.log.appendLine(message);if(!this.disposed&&error.code!=='ASTRO_LOCK_BUSY')void this.vscode.window.showWarningMessage(message)}}
  publicationLog(status,job,extra={}){
    const e=job.error;
    this.log.appendLine('AstroNvim settings publication '+JSON.stringify({status,id:job.id,operation:job.context.operation,
      target:job.context.target,generation:job.generation,elapsed_ms:Date.now()-job.started,attempts:job.attempts,
      error:{name:e.name,message:e.message,stack:e.stack,code:e.code,errno:e.errno,syscall:e.syscall,path:e.path,dest:e.dest},...extra}));
  }
  deferPublication(error){
    if(!error.astroPublication)return false;
    const job={id:this.store.owner+'-publication-'+(++this.publicationCounter),error,context:error.astroPublication,
      token:this.activeToken,generation:this.generation,planKey:this.planKey,started:Date.now(),attempts:1};
    this.pending=job;this.needsRestore=true;this.hasLease=false;this.publicationLog('pending',job);return true;
  }
  finishCancellation(job,reason){
    try{
      const done=this.store.cancelAcquire(job.context);if(this.pending===job)this.pending=null;
      if(this.cancelRequired===job)this.cancelRequired=null;
      this.hasLease=false;this.needsRestore=!done;this.initialRecovery=false;this.lastReleaseAttempt=Date.now();
      this.publicationLog('canceled',job,{reason});return true;
    }catch(error){
      if(this.pending===job)this.pending=null;
      if(error.astroPublication?.operation==='restore'){
        this.cancelRequired=null;this.failed=null;
        this.publicationLog('canceled',job,{reason:'transferred_to_restore'});this.deferPublication(error);return false;
      }
      // Preserve the known-unpublished transaction until cancellation actually
      // succeeds. Generic crash recovery must not mistake a later user value
      // for our failed publication.
      this.cancelRequired=job;this.failed={generation:this.generation,error,operation:'acquire',cancelComplete:false};
      throw error;
    }
  }
  cancelPendingAcquire(reason){
    const job=this.pending;return !job||job.context.operation!=='acquire'||this.finishCancellation(job,reason);
  }
  finishRequiredCancellation(reason){
    const job=this.cancelRequired;if(!job)return true;
    this.suppressed.add(job.token);
    const done=this.finishCancellation(job,reason);if(done)this.failed=null;return done;
  }
  advancePublication(){
    const job=this.pending;if(!job)return true;job.attempts++;
    try{
      if(job.context.operation==='acquire'){
        const result=this.store.resumeAcquire(job.context);this.pending=null;
        if(result.status==='canceled'){
          this.hasLease=false;this.needsRestore=false;this.initialRecovery=false;this.suppressed.add(job.token);
          this.publicationLog('canceled',job,{reason:result.reason});return false;
        }
        this.hasLease=true;this.needsRestore=true;this.lastSync=Date.now();
      }else{
        const done=this.store.resumeRestore(job.context);this.pending=null;this.hasLease=false;this.needsRestore=!done;
        this.initialRecovery=false;this.lastReleaseAttempt=Date.now();
      }
      this.lastError='';this.publicationLog('resolved',job);return true;
    }catch(error){
      this.pending=null;this.failed={generation:this.generation,error,operation:job.context.operation,cancelComplete:false};this.hasLease=false;this.needsRestore=true;
      this.publicationLog('failed',job,{final_error:{name:error.name,message:error.message,stack:error.stack,code:error.code,errno:error.errno,syscall:error.syscall,path:error.path,dest:error.dest}});
      if(job.context.operation==='acquire'){
        try{if(this.finishCancellation(job,'failed_acquire_cleanup'))this.failed.cancelComplete=true}
        catch(cleanup){this.error(cleanup)}
      }
      this.error(error);return false;
    }
  }
  releaseForTransition(periodic=false,all=false,intent){
    const pendingAtEntry=this.pending;
    // A new explicit Profile identity is a new intent. Repeated guard polls for
    // the same identity cannot restart a permanently failed transaction.
    if(intent!==undefined&&intent!==this.transitionIntent){
      this.transitionIntent=intent;
      if(this.failed?.operation==='restore')this.lastReleaseAttempt=0;
      if(!this.finishRequiredCancellation('profile_changed'))return false;
      this.failed=null;
    }
    this.cancelPendingAcquire('intent_changed');
    if(this.pending){if(!periodic||this.pending!==pendingAtEntry)return false;if(!this.advancePublication())return false}
    if(this.cancelRequired)throw this.failed.error;
    if(this.failed){
      if(this.failed.operation==='acquire'&&this.failed.cancelComplete)return true;
      throw this.failed.error;
    }
    try{this.release(all);return true}catch(error){if(this.deferPublication(error))return false;throw error}
  }
  plan(){
    const effective={},inspect={},targets=new Map();
    const workspaceUri=this.vscode.workspace.workspaceFile;
    const folderUris=(this.vscode.workspace.workspaceFolders||[]).map(f=>f.uri);
    const remote=(workspaceUri&&workspaceUri.scheme!=='file')||folderUris.some(uri=>uri.scheme!=='file');
    for(const setting of SETTINGS){
      const split=setting.key.lastIndexOf('.'),cfg=this.vscode.workspace.getConfiguration(setting.key.slice(0,split));
      const name=setting.key.slice(split+1),info=cfg.inspect(name)||{};
      effective[setting.key]=cfg.get(name);inspect[setting.key]=info;
      if(remote)continue;
      let file=this.profileSettings,keys=[setting.key];
      if(info.workspaceValue!==undefined){
        if(workspaceUri){file=workspaceUri.fsPath;keys=['settings',setting.key]}
        else{
          if(folderUris.length!==1)return{unsupported:true,effective,satisfied:false,reason:'Cannot safely resolve the local workspace override of '+setting.key};
          file=path.join(folderUris[0].fsPath,'.vscode','settings.json');
        }
      }
      file=path.resolve(file);
      const identity=process.platform==='win32'?file.toLowerCase():file;
      if(!targets.has(identity))targets.set(identity,{file,entries:[]});
      targets.get(identity).entries.push({keys,value:setting.value});
    }
    const satisfied=SETTINGS.every(x=>effective[x.key]===x.value);
    if(remote)return{unsupported:true,effective,satisfied,reason:'The remote workspace configuration cannot be safely backed up by this local transaction. AstroNvim mouse routing requires '+SETTINGS.map(x=>x.key+'='+JSON.stringify(x.value)).join(' and ')+'.'};
    const rows=[...targets.values()];
    return{targets:rows,key:JSON.stringify(rows.map(x=>[x.file,x.entries])),effective,inspect,satisfied};
  }
  release(all=false){
    // Another active window will perform the final restore. Recheck a waiting
    // owner only on the lease heartbeat so ordinary terminal polls stay cheap.
    if(!this.hasLease&&this.needsRestore&&!all&&!this.initialRecovery&&Date.now()-this.lastReleaseAttempt<5000)return;
    if(this.hasLease||this.needsRestore||all||this.initialRecovery){const done=this.store.release({all:all||this.initialRecovery});this.hasLease=false;this.needsRestore=!done;this.initialRecovery=false;this.lastReleaseAttempt=Date.now()}
  }
  suppress(seen,reason){
    for(const token of seen)this.suppressed.add(token);this.release();
    if(reason&&reason!==this.lastError){
      this.lastError=reason;this.log.appendLine(reason);
      // Respecting an intentional user preference is informational. A warning
      // toast intercepts the next Escape even while the terminal has focus.
      // Keep the notice visible without replacing terminal input handling.
      if(this.notice)this.notice.dispose();
      this.notice=this.vscode.window.setStatusBarMessage('AstroNvim: '+reason,8000);
    }
  }
  update(active,seen,periodic=false){
    if(this.disposed)return false;
    const pendingAtEntry=this.pending;
    try{
      if(active!==this.activeToken){
        this.activeToken=active;this.generation++;
        if(!this.finishRequiredCancellation('activation_changed'))return false;
        this.failed=null;
      }
      if(this.pending){
        if(this.pending.context.operation==='acquire'){
          if(active!==this.pending.token||this.suppressed.has(active))this.cancelPendingAcquire('activation_changed');
          else if(this.dirty){
            const plan=this.plan();
            if(plan.unsupported||plan.key!==this.pending.planKey){this.cancelPendingAcquire('plan_changed');for(const token of seen)this.suppressed.add(token)}
          }
        }
        if(this.pending){if(!periodic||this.pending!==pendingAtEntry)return false;if(!this.advancePublication())return false}
      }
      if(this.failed)return false;
      if(!this.registered){this.store.register(this.profileSettings);this.registered=true}
      if(!active||this.suppressed.has(active)){
        // Observe a user override before the last departing owner archives it.
        // Otherwise this window could reacquire the same old token on refocus.
        if(this.hasLease){this.store.acquire();this.lastSync=Date.now();if(this.store.userOverrides.size){this.suppress(seen,'AstroNvim mouse setting was changed by the user. The new preference is preserved for the current sessions.');return false}}
        this.release();return false;
      }
      if(this.initialRecovery)this.release();
      if(this.hasLease){
        // Configuration events cover ordinary user edits; the 5-second lease
        // renewal also detects malformed/on-disk changes. Do not add filesystem
        // stats to each 150-ms terminal-title poll.
        if(!this.dirty&&Date.now()-this.lastSync<5000)return true;
        this.store.acquire();this.lastSync=Date.now();
        if(this.store.userOverrides.size){this.suppress(seen,'AstroNvim mouse setting was changed by the user. The new preference is preserved; automatic mouse takeover is suspended for the current sessions.');return false}
        if(!this.dirty)return true;
      }
      const plan=this.plan();this.dirty=false;
      if(plan.unsupported){
        this.release();
        if(plan.satisfied)return true;
        this.error(Error(plan.reason));return false;
      }
      if(this.hasLease&&plan.key!==this.planKey){
        this.suppress(seen,'The effective AstroNvim mouse setting was changed in another configuration layer. The user preference is preserved for the current sessions.');return false;
      }
      if(plan.key!==this.planKey){
        this.release();this.store=new this.Store();for(const target of plan.targets)this.store.register(target.file,target.entries);this.planKey=plan.key;this.needsRestore=true;
      }
      this.store.acquire();this.lastSync=Date.now();this.hasLease=true;this.needsRestore=true;this.lastError='';
      if(this.store.userOverrides.size){this.suppress(seen,'AstroNvim mouse setting was changed by the user in another window. The new preference is preserved for the current sessions.');return false}
      this.log.appendLine('AstroNvim mouse routing: '+plan.targets[0].file+'; previous effective='+JSON.stringify(plan.effective)+'; configuration='+JSON.stringify(plan.inspect));return true;
    }catch(error){if(!this.deferPublication(error))this.error(error);return false}
  }
  restore(seen){for(const token of seen)this.suppressed.add(token);try{if(!this.finishRequiredCancellation('manual_restore'))return false;this.failed=null;return this.releaseForTransition(false,true)}catch(error){this.error(error);return false}}
  dispose(){
    if(this.disposing)return this.disposing;if(this.disposed)return;
    this.disposed=true;if(this.notice)this.notice.dispose();if(this.change)this.change.dispose();
    try{
      if(!this.finishRequiredCancellation('dispose')){ /* a restore intent remains below */ }
      this.cancelPendingAcquire('dispose');
      if(!this.pending){if(this.failed){this.error(this.failed.error);return}try{this.release()}catch(error){if(!this.deferPublication(error))throw error}}
      if(this.pending){
        // The normal path stays synchronous. During shutdown only, a known
        // restore publication gets one bounded existing-poll-sized opportunity.
        // deactivate awaits this Promise; no callback can survive disposal.
        this.disposing=new Promise((resolve,reject)=>setTimeout(()=>{try{resolve(this.advancePublication())}catch(error){reject(error)}},150));return this.disposing;
      }
    }catch(error){this.error(error)}
  }
}
module.exports={MouseController};
