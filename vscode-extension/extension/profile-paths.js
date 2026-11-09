'use strict';
const fs=require('fs'),path=require('path');
const SETTING='profileFiles';
function failure(message){const error=Error('Cannot safely determine the active VS Code Profile: '+message+'. Original settings and shortcuts were not changed. For a named Profile, configure portableAstro.profileFiles in that Profile\'s User settings with its Settings JSON and Keyboard Shortcuts JSON absolute paths.');error.code='ASTRO_PROFILE_UNRESOLVED';return error}
function object(value){return value!==null&&typeof value==='object'&&!Array.isArray(value)}
function empty(value){return value===undefined||(object(value)&&Object.keys(value).length===0)}
function optionalStat(file){try{return fs.lstatSync(file)}catch(error){if(error.code==='ENOENT')return null;throw failure('cannot inspect local Profile resources ('+error.code+')')}}
function userDirectory(context){
 const uri=context.globalStorageUri;
 if(!uri||!['file','vscode-userdata'].includes(uri.scheme)||uri.authority||!path.isAbsolute(uri.fsPath))throw failure('non-local extension storage');
 const global=path.dirname(path.resolve(uri.fsPath)),user=path.dirname(global);
 if(path.basename(global).toLowerCase()!=='globalstorage'||path.basename(user).toLowerCase()!=='user')throw failure('unrecognized extension storage layout');
 // Existing parents are required so a typo cannot create a second User tree.
 if(!fs.statSync(user).isDirectory()||!fs.statSync(global).isDirectory())throw failure('User storage directory is absent');
 return fs.realpathSync(user);
}
function explicitFile(user,file,name){
 if(typeof file!=='string'||!path.isAbsolute(file)||path.basename(file).toLowerCase()!==name)throw failure('explicit '+name+' path must be absolute and name the expected file');
 const parent=fs.realpathSync(path.dirname(file)),rel=path.relative(user,parent),parts=rel.split(path.sep);
 if(rel!==''&&(path.isAbsolute(rel)||parts.length!==2||parts[0].toLowerCase()!=='profiles'||!parts[1]||parts[1]==='..'))throw failure('explicit '+name+' is outside User or a direct User/profiles child');
 const result=path.join(parent,name);
 const stat=optionalStat(result);
 if(stat&&(!stat.isFile()||stat.isSymbolicLink()||fs.realpathSync(result)!==result))throw failure(name+' is a redirected or non-file resource');
 return result;
}
function resolveProfile(vscode,context){
 const user=userDirectory(context),config=vscode.workspace.getConfiguration('portableAstro'),info=config.inspect(SETTING)||{};
 // A project must never choose which user preference files the client writes.
 for(const key of ['workspaceValue','workspaceFolderValue','workspaceLanguageValue','workspaceFolderLanguageValue'])if(info[key]!==undefined)throw failure('workspace overrides for portableAstro.profileFiles are not accepted');
 const declared=info.globalValue;
 if(declared!==undefined&&declared!==null){
  if(!object(declared)||Object.keys(declared).sort().join(',')!=='keybindings,settings')throw failure('explicit profileFiles requires exactly settings and keybindings');
  return{id:'explicit',name:'Explicit user configuration',settings:explicitFile(user,declared.settings,'settings.json'),keybindings:explicitFile(user,declared.keybindings,'keybindings.json'),source:'Explicit current User configuration; no automatic Profile inference',user};
 }
 // These synchronous checks are used only at activation/new acquisition and a
 // five-second identity heartbeat, not on each terminal-title/input poll.
 const profiles=path.join(user,'profiles');
 const profileStat=optionalStat(profiles);
 if(profileStat&&(!profileStat.isDirectory()||profileStat.isSymbolicLink()))throw failure('Profile directory has an unrecognized resource type');
 if(profileStat&&fs.readdirSync(profiles).length!==0)throw failure('named, temporary, or internal Profile directories exist');
 const metadata=path.join(user,'globalStorage','storage.json');
 const metadataStat=optionalStat(metadata);
 if(metadataStat){
  if(!metadataStat.isFile()||metadataStat.isSymbolicLink())throw failure('Profile metadata is a redirected or non-file resource');
  let data;try{data=JSON.parse(fs.readFileSync(metadata,'utf8'))}catch{throw failure('Profile metadata is unreadable or invalid')}
  if(!object(data))throw failure('Profile metadata has an unknown shape');
  if(data.userDataProfiles!==undefined&&(!Array.isArray(data.userDataProfiles)||data.userDataProfiles.length!==0))throw failure('named Profile metadata exists');
  if(data.profileAssociations!==undefined){
   const a=data.profileAssociations;
   if(!object(a)||Object.keys(a).some(k=>!['workspaces','emptyWindows'].includes(k))||!empty(a.workspaces)||!empty(a.emptyWindows))throw failure('Profile associations exist or have an unknown shape');
  }
 }
 return{id:'default-only',name:'Default (only local Profile)',settings:explicitFile(user,path.join(user,'settings.json'),'settings.json'),keybindings:explicitFile(user,path.join(user,'keybindings.json'),'keybindings.json'),source:'Default-only local layout guard; not a public Profile identity API',user};
}
module.exports={resolveProfile,userDirectory,explicitFile,SETTING};
