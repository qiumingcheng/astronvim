'use strict';
const vscode = require('vscode');
const {KeyStore}=require('./key-store');
const {MouseController}=require('./mouse-controller');
const {SettingsStore}=require('./settings-store');
const {resolveProfile}=require('./profile-paths');
const bindings=require('./keybindings.json');
let disposeActive;

function activate(context) {
  const seen = new Set();
  const suppressed = new Set();
  const restores = new Set();
  let enabled,focusRouting;
  let store=new KeyStore(bindings);
  const log=vscode.window.createOutputChannel('AstroNvim Keyboard');
  // VS Code disposes subscriptions before awaiting deactivate. The Output
  // channel remains owned here until any bounded settings restore settles.
  let mouse,profile,lastProfileError='',profileWarningShown=false,nextProfileAttempt=0;
  function ensureProfile(notify=false,running=false,periodic=false){
    if(profile&&!lastProfileError&&(hasLease||!running)&&Date.now()<nextProfileAttempt)return true;
    if(!profile&&Date.now()<nextProfileAttempt){if(notify&&lastProfileError&&!profileWarningShown){profileWarningShown=true;void vscode.window.showWarningMessage(lastProfileError)}return false}
    let resolved;
    try{resolved=resolveProfile(vscode,context)}catch(error){
      // Only a resolver failure creates an invalid identity. A failure while
      // releasing the old valid Profile must keep that same transition intent.
      if(profile)try{if(!dropProfile(periodic,'invalid:'+String(error)))return false}catch(restoreError){log.appendLine('Profile restoration failed: '+String(restoreError))}
      const message=String(error);nextProfileAttempt=Date.now()+1000;
      if(message!==lastProfileError){lastProfileError=message;profileWarningShown=false;log.appendLine(message)}
      if(notify&&!profileWarningShown){profileWarningShown=true;void vscode.window.showWarningMessage(message)}
      return false;
    }
    try{
      if(profile&&(profile.settings!==resolved.settings||profile.keybindings!==resolved.keybindings)&&!dropProfile(periodic,JSON.stringify([resolved.settings,resolved.keybindings])))return false;
      if(!profile){
        store.register(resolved.keybindings);mouse=new MouseController(vscode,resolved.settings,log);profile=resolved;
        log.appendLine('AstroNvim Profile: '+resolved.name+'; keybindings='+resolved.keybindings+'; settings='+resolved.settings+'; '+resolved.source);
      }
      nextProfileAttempt=Date.now()+5000;lastProfileError='';profileWarningShown=false;return true;
    }catch(error){
      const message='Profile transaction failed: '+String(error);
      if(message!==lastProfileError){lastProfileError=message;log.appendLine(message)}
      return false;
    }
  }
  function dropProfile(periodic=false,intent){
    store.release();if(mouse){if(!mouse.releaseForTransition(periodic,false,intent))return false;mouse.dispose()}
    mouse=undefined;profile=undefined;store=new KeyStore(bindings);hasLease=false;needsRestore=true;
    return true;
  }
  let hasLease=false,needsRestore=true,lastError='';
  function syncBackup(running,all=false){
    try{
      if(running){store.acquire();hasLease=true;needsRestore=true;lastError='';return true}
      if(hasLease||needsRestore||all){const restored=store.release({all});hasLease=false;needsRestore=!restored}
      lastError='';return false;
    }catch(error){
      const message=String(error);
      if(message!==lastError){
        log.appendLine(message);lastError=message;
        if(error.code==='ASTRO_LEGACY_CLIENT')void vscode.window.showWarningMessage(message);
      }
      // A competing new client briefly holding the lock must not disable an
      // already functioning terminal's shortcuts. Legacy protocols are blocked.
      return error.code==='ASTRO_LOCK_BUSY'&&hasLease;
    }
  }
  function token(terminal) {
    const match = terminal && /^AstroNvimPortable:active:([\w-]+)$/.exec(terminal.name);
    return match && match[1];
  }
  function restore() {
    for (const t of vscode.window.terminals) { const id = token(t); if (id) seen.add(id); }
    for (const id of seen) suppressed.add(id);
    setEnabled(false);
    setFocusRouting(false);
    // Manual recovery uses HOME transaction registrations even if the current
    // Profile cannot be identified. Live owners in other windows are respected.
    syncBackup(false,true);
    if(mouse)mouse.restore(seen);
    else try{new SettingsStore().release({all:true})}catch(error){log.appendLine(String(error));void vscode.window.showWarningMessage(String(error))}
  }
  function setEnabled(value) {
    if (enabled === value) return;
    enabled = value;
    void vscode.commands.executeCommand('setContext', 'portableAstro.active', value);
  }
  function setFocusRouting(value) {
    if (focusRouting === value) return;
    focusRouting = value;
    void vscode.commands.executeCommand('setContext', 'portableAstro.focusRouting', value);
  }
  function update(periodic=false) {
    for (const terminal of vscode.window.terminals) {
      const id = token(terminal);
      if (id) seen.add(id);
      const match = /^AstroNvimPortable:restore:([\w-]+)$/.exec(terminal.name);
      if (match && !restores.has(match[1])) {
        restores.add(match[1]);
        restore();
      }
    }
    const active = token(vscode.window.activeTerminal);
    const running=vscode.window.terminals.some(t=>{const id=token(t);return id&&!suppressed.has(id)});
    // The manifest's native keybindings need only an identified terminal and
    // keyboard focus. They never write Profile files, so a conservative Profile
    // guard must not disable them. Keep all preference transaction guards below.
    setFocusRouting(Boolean(active && !suppressed.has(active)));
    if(!ensureProfile(running,running,periodic)){setEnabled(false);return}
    const ready=syncBackup(running);
    mouse.update(active&&!suppressed.has(active)?active:null,seen,periodic);
    setEnabled(Boolean(ready && active && !suppressed.has(active)));
  }
  // Terminal.name follows OSC titles, including titles emitted over SSH.
  // VS Code's stable API has no terminal-title-change event, so poll only names.
  const timer = setInterval(()=>update(true), 150);
  const events = [
    vscode.window.onDidChangeActiveTerminal(()=>update()),
    vscode.window.onDidCloseTerminal(()=>update()),
    vscode.window.onDidOpenTerminal(()=>update()),
    vscode.commands.registerCommand('portableAstro.restoreKeys', restore),
    vscode.workspace.onDidChangeConfiguration(event=>{if(event.affectsConfiguration('portableAstro.profileFiles')){nextProfileAttempt=0;update()}}),
  ];
  // Shell integration reports completion of a host command, including a direct
  // SSH launch. Re-read all titles: an event alone must never release a lease.
  // Older clients and persistent SSH shells retain the 150 ms title fallback.
  if (typeof vscode.window.onDidEndTerminalShellExecution === 'function') {
    events.push(vscode.window.onDidEndTerminalShellExecution(() => {
      if (hasLease || needsRestore) update();
    }));
  }
  let disposal;
  disposeActive = () => {
    if(disposal)return disposal;
    clearInterval(timer);
    events.forEach(event => event.dispose());
    try{store.release()}catch(error){log.appendLine(String(error))}
    const mouseRestore=mouse&&mouse.dispose();
    // A closed renderer cancels command RPCs during host shutdown. Skip a
    // redundant reset; tolerate only that cancellation for this UI context.
    // Settings restoration and every other failure still retain their errors.
    function resetContext(key,alreadyDisabled){return alreadyDisabled?Promise.resolve():vscode.commands.executeCommand('setContext', key, false).catch(error=>{
      if(error?.name!=='Canceled'||error?.message!=='Canceled')throw error;
      log.appendLine('AstroNvim shutdown: context reset canceled by closing renderer.');
    })}
      disposal=Promise.allSettled([mouseRestore,
        resetContext('portableAstro.active',enabled===false),
        resetContext('portableAstro.focusRouting',focusRouting===false),
      ]).then(results=>{
        for(const result of results)if(result.status==='rejected')log.appendLine('AstroNvim shutdown failure: '+JSON.stringify({name:result.reason?.name,message:result.reason?.message,stack:result.reason?.stack,code:result.reason?.code,errno:result.reason?.errno,path:result.reason?.path,dest:result.reason?.dest}));
        log.dispose();
        const failed=results.find(result=>result.status==='rejected');if(failed)throw failed.reason;
      });
    return disposal;
  };
  context.subscriptions.push({dispose: () => void disposeActive()});
  update();
  return {isEnabled: () => enabled};
}
function deactivate() { return disposeActive && disposeActive(); }
module.exports = { activate, deactivate };
