/* Mi Cepillo — lectura BLE del Oclean X (protocolo Type-1 / OCLEANY3M)
   Referencia del protocolo: github.com/deniskie/ha-oclean-integration (MIT) */
(function(){
'use strict';

var APP_VERSION = '14';

/* ---------- UUIDs GATT ---------- */
var SVC       = '8082caa8-41a6-4021-91c6-56f9b954cc18';
var C_WRITE   = '9d84b9a3-000c-49d8-9183-855b673fbb85'; // escritura general (fbb85)
var C_NOTIFY  = '5f78df94-798c-46f5-990a-855b673fbb86'; // respuestas estado (fbb86)
var C_SEND    = '5f78df94-798c-46f5-990a-855b673fbb89'; // comandos de sesión (fbb89)
var C_RECV    = '5f78df94-798c-46f5-990a-855b673fbb90'; // registros *B# (fbb90)
var BATT_SVC  = 0x180f, BATT_CHAR = 0x2a19;
var DIS_SVC   = 0x180a, DIS_MODEL = 0x2a24;

/* ---------- Programas de cepillado (pNum -> nombre) ---------- */
var SCHEMES = {
  0:'Limpieza estándar', 72:'Limpieza media-fuerte', 73:'Limpieza fuerte',
  74:'Cuidado sensible', 75:'Blanqueamiento diario', 76:'Blanqueamiento medio',
  77:'Súper blanqueamiento', 78:'Limpieza suave', 79:'SPA suave',
  80:'SPA estándar', 81:'SPA profundo', 82:'Después de dulces',
  83:'Fresco post-comida', 84:'Masaje de encías', 85:'Cuidado de encías',
  86:'Blanqueamiento inicial', 87:'Limpieza con brackets', 88:'Limpieza rápida',
  89:'Viaje', 90:'Cuidado gestación'
};
var ZONES = ['SI ext','SI int','II ext','II int','SD ext','SD int','ID ext','ID int'];
var ZONES_FULL = ['Superior izq. exterior','Superior izq. interior','Inferior izq. exterior','Inferior izq. interior',
                  'Superior der. exterior','Superior der. interior','Inferior der. exterior','Inferior der. interior'];

/* Esquemas de cepillado OCLEANY3 (pnum -> [nombre, [[gear,seg],...]]) */
var GEAR_ENC={1:5,2:6,3:7,4:8,5:17,6:18,7:19,8:20,9:21,10:22,11:23,12:24};
var SCHEMES={
  0:['Limpieza estándar',[[2,30],[2,30],[2,30],[2,30]]],
  72:['Limpieza media-fuerte',[[16,30],[16,30],[24,30],[16,30],[16,30],[37,30]]],
  73:['Limpieza fuerte',[[38,30],[24,30],[24,30],[24,30],[24,30],[32,30]]],
  74:['Sensible post-lavado',[[8,30],[8,30],[37,30],[8,30],[8,30]]],
  75:['Blanqueo diario',[[34,30],[34,30],[24,30],[16,30],[16,30]]],
  76:['Blanqueo medio',[[32,30],[35,30],[24,30],[24,30],[35,30]]],
  77:['Súper blanqueo',[[32,30],[36,30],[32,30],[36,30],[32,30]]],
  78:['Limpieza sensible',[[37,30],[41,30],[41,30],[41,30],[41,30],[41,30]]],
  79:['SPA suave',[[8,30],[33,30],[33,30],[37,30],[37,30],[8,30]]],
  80:['SPA estándar',[[38,30],[38,30],[34,30],[34,30],[16,30],[16,30]]],
  81:['SPA profundo',[[39,30],[35,30],[24,30],[24,30],[39,30],[35,30]]],
  82:['Tras dulces',[[18,30],[18,30],[12,30],[12,30]]],
  83:['Frescor post-comida',[[41,30],[41,30],[1,30],[41,30],[41,30]]],
  84:['Masaje de encías',[[38,30],[38,30],[38,30],[38,30]]],
  85:['Cuidado de encías',[[8,30],[8,30],[37,30],[8,30],[8,30],[37,20],[8,30]]],
  86:['Blanqueo principiante',[[33,30],[6,30],[33,30],[6,30],[6,30]]],
  87:['Limpieza con brackets',[[8,30],[8,30],[8,30],[8,30],[8,30],[8,30]]],
  88:['Limpieza rápida',[[30,20],[30,20],[30,20],[30,20]]],
  89:['Viaje',[[17,30],[17,30],[35,30],[35,30]]],
  90:['Cuidado gestación',[[12,30],[12,30],[20,30],[38,30],[12,30],[12,30]]]
};
function buildSchemePackets(pnum){
  var s=SCHEMES[pnum]; if(!s) return null;
  var pl=[0x02,0x06,pnum&0xff,s[1].length&0xff];
  s[1].forEach(function(st){ pl.push(GEAR_ENC[st[0]]||0, st[0]&0xff, st[1]&0xff); });
  pl.push(0x00,0x05);
  if(pl.length>20){ return [pl.slice(0,16).concat([0x2a,0x2b]), [0x02,0x0b].concat(pl.slice(16))]; }
  return [pl];
}
function zoneClasses(s){
  if(!s||!s.zones) return null;
  var sum=0; s.zones.forEach(function(v){sum+=(+v||0);});
  var dur=s.dur||s.durSched||120;
  return s.zones.map(function(v){
    if(!v||sum<=0) return 'bad';
    var norm=v/sum*dur;
    return norm>=9?'good':(norm>=4?'mid':'bad');
  });
}
function sampleSessions(){
  var t=new Date();
  function at(h,m){ var d=new Date(t); d.setHours(h,m,0,0); return d.getTime(); }
  return [
    {ts:at(7,42),pnum:0,dur:120,durSched:120,score:92,zones:[120,110,90,80,115,100,70,60],coverage:88,sample:true},
    {ts:at(14,15),pnum:88,dur:80,durSched:80,score:71,zones:[80,40,20,0,90,60,30,10],coverage:63,sample:true},
    {ts:at(22,5),pnum:0,dur:118,durSched:120,score:84,zones:[110,90,70,50,100,95,55,40],coverage:75,sample:true}
  ];
}
function todaySessions(){
  var k=dayKey(Date.now());
  var real=store.sessions.filter(function(s){return dayKey(s.ts)===k;});
  return real.length?real:(store.sessions.length?[]:sampleSessions());
}

/* Tabla de zonas horarias Oclean (minutos) para la calibración 0201 */
var TZ_MIN = [-720,-660,-600,-540,-480,-420,-360,-300,-240,-210,-180,-120,-60,0,60,120,180,210,240,270,300,330,345,360,390,420,480,540,570,600,660,720,780];

/* ---------- Registro de diagnóstico (persistente para poder copiarlo tras reiniciar) ---------- */
var DBGKEY='cepillo-dbg-v1';
var diag=[];
try{ diag=JSON.parse(localStorage.getItem(DBGKEY)||'[]'); }catch(e){}
function dlog(msg){
  var d=new Date();
  diag.push(pad(d.getHours())+':'+pad(d.getMinutes())+':'+pad(d.getSeconds())+'.'+String(d.getMilliseconds()).padStart(3,'0')+' '+msg);
  if(diag.length>600) diag.splice(0,diag.length-600);
  try{ localStorage.setItem(DBGKEY,JSON.stringify(diag)); }catch(e){}
}
function hex(u8){ var s=''; for(var i=0;i<u8.length;i++) s+=(u8[i]<16?'0':'')+u8[i].toString(16); return s; }

/* ---------- Almacén ---------- */
var KEY = 'cepillo-data-v1';
var store = { sessions:[], battery:null, headTimes:null, headDays:null, model:null, lastSync:null, lastSess:null, brushMode:null, areaRemind:null, overPressure:null, pending:{} };
try { var raw = localStorage.getItem(KEY); if (raw) { var p = JSON.parse(raw); for (var k in p) store[k] = p[k]; } } catch(e){}
function save(){ try { localStorage.setItem(KEY, JSON.stringify(store)); } catch(e){} }

/* ---------- Estado UI ---------- */
var state = { tab:'hoy', connecting:false, status:'', statusKind:'', showAllDevices:false, sheet:null, sel:0 };
var root = document.getElementById('root');

function esc(s){ return String(s).replace(/[&<>"]/g, function(c){ return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]; }); }
function pad(n){ return n<10?'0'+n:''+n; }
function fmtDur(s){ if(s==null) return '—'; return Math.floor(s/60)+':'+pad(s%60); }
function fmtTime(ts){ var d=new Date(ts); return pad(d.getHours())+':'+pad(d.getMinutes()); }
function dayKey(ts){ var d=new Date(ts); return d.getFullYear()+'-'+pad(d.getMonth()+1)+'-'+pad(d.getDate()); }
function dayLabel(ts){
  var d=new Date(ts), now=new Date();
  var today=dayKey(now.getTime()), yest=dayKey(now.getTime()-864e5);
  var k=dayKey(ts);
  if(k===today) return 'Hoy';
  if(k===yest) return 'Ayer';
  return d.toLocaleDateString('es-ES',{weekday:'long',day:'numeric',month:'long'});
}
function schemeName(pnum){ var s=SCHEMES[pnum]; return s?s[0]:(pnum==null?'Cepillado':'Programa '+pnum); }
function scoreClass(s){ return s==null?'':(s>=80?'score-good':(s>=50?'score-mid':'score-bad')); }

/* ---------- Estadísticas ---------- */
function sessionsToday(){ var k=dayKey(Date.now()); return store.sessions.filter(function(s){return dayKey(s.ts)===k;}).length; }
function streak(){
  var days={}; store.sessions.forEach(function(s){ days[dayKey(s.ts)]=1; });
  var n=0, t=Date.now();
  if(!days[dayKey(t)]) t-=864e5; // si hoy aún no, empezar por ayer
  while(days[dayKey(t)]){ n++; t-=864e5; }
  return n;
}
function avgScore7(){
  var lim=Date.now()-7*864e5, arr=store.sessions.filter(function(s){return s.ts>=lim && s.score!=null;});
  if(!arr.length) return null;
  return Math.round(arr.reduce(function(a,s){return a+s.score;},0)/arr.length);
}

/* ---------- Toasts (uno a la vez, ~3 s) ---------- */
var toastTimer=null;
function toast(msg){
  var box=document.querySelector('.mg-toasts'); if(!box) return;
  box.innerHTML='';
  var el=document.createElement('div'); el.className='mg-toast'; el.textContent=msg;
  box.appendChild(el);
  requestAnimationFrame(function(){ el.classList.add('show'); });
  clearTimeout(toastTimer);
  toastTimer=setTimeout(function(){ el.classList.remove('show'); setTimeout(function(){ el.remove(); },350); },3000);
}

/* ---------- Render ---------- */
function render(){
  var html='';
  html+='<div class="mg-app'+(state.sheet?' sheet-open':'')+'">';
  html+='<div class="mg-scroll" id="mg-scroll">';
  html+='<header class="mg-header"><h1 class="mg-title">Oclean</h1><img class="head-logo" src="./icon-v12-192.png" alt="Oclean"></header>';
  if(state.tab==='hoy') html+=viewHoy();
  else if(state.tab==='historial') html+=viewHistorial();
  else html+=viewAjustes();
  html+='</div>';
  html+='<nav class="mg-tabs">'
    + tabBtn('hoy','🪥','Hoy')
    + tabBtn('historial','🗓️','Historial')
    + tabBtn('ajustes','⚙️','Ajustes')
    + '</nav>';
  html+='<button class="update-pill" id="update-pill" hidden>⬇️ Nueva versión · pulsa para actualizar</button>';
  html+='<div class="mg-toasts"></div>';
  html+='</div>';
  if(window.Denture3D) window.Denture3D.disposeAll();
  root.innerHTML=html;
  wire();
  mountDentures();
  if(state.sheet) renderSheet();
}
function mountDentures(){
  if(!window.Denture3D) return;
  document.querySelectorAll('canvas.denture3d').forEach(function(cv){
    var z=null; try{ z=JSON.parse(cv.dataset.zones||'null'); }catch(e){}
    if(!z) return;
    if(cv.dataset.live==='1') window.Denture3D.mountLive(cv,z);
    else window.Denture3D.drawStatic(cv,z);
  });
}
window.mountDentures=mountDentures;
function tabBtn(id,ico,label){
  return '<button class="mg-tab-btn" data-tab="'+id+'"'+(state.tab===id?' aria-current="page"':'')+'><span class="mg-tab-ico">'+ico+'</span>'+label+'</button>';
}

function battCard(){
  if(store.battery==null) return '';
  var b=store.battery, cls=b<=20?'low':(b<=50?'mid':'');
  return '<div class="mg-card"><div class="card-label">Batería</div><div class="batt-row">'
    +'<span class="batt-ico">'+(b<=20?'🪫':'🔋')+'</span>'
    +'<div class="batt-bar"><div class="batt-fill '+cls+'" style="width:'+b+'%"></div></div>'
    +'<span class="batt-pct">'+b+'%</span></div></div>';
}
function headCard(){
  if(store.headTimes==null && store.headDays==null) return '';
  var txt=[];
  if(store.headDays!=null) txt.push(store.headDays+(store.headDays===1?' día':' días'));
  if(store.headTimes!=null) txt.push(store.headTimes+' cepillados');
  return '<div class="mg-card"><div class="card-label">Cabezal</div><div class="batt-row">'
    +'<span class="batt-ico">✨</span><div style="font-size:15px;font-weight:600">'+txt.join(' · ')+'</div></div>'
    +'<div class="settings-note">Cuando cambies el cabezal, reinícialo desde la app oficial o dímelo y lo añado.</div></div>';
}

function sessDetail(s){
  var z=zoneClasses(s);
  return '<div class="mg-card sess-card'+(s.sample?' sample':'')+'">'
    +(s.sample?'<span class="sample-tag">Ejemplo</span>':'')
    +'<div class="lens-top">'+scoreRing(s.score,64)
    +'<div class="lens-info"><div class="lens-scheme">'+esc(schemeName(s.pnum))+'</div>'
    +'<div class="lens-when">'+fmtTime(s.ts)+'</div>'
    +'<div class="lens-dur">⏱ '+fmtDur(s.dur)+' · Cobertura '+(s.coverage!=null?s.coverage+'%':'—')+'</div></div></div></div>'
    +(z?'<div class="denture-wrap"><canvas class="denture3d" data-live="1" data-zones=\''+JSON.stringify(z)+'\'></canvas></div>'
       :'<div class="settings-note" style="text-align:center">Sin datos de zonas</div>');
}
function viewHoy(){
  var h='';
  var pend=Object.keys(store.pending||{}).length;
  // Cepillo: imagen + batería + cabezal + sync
  h+='<div class="mg-card brush-card">'
    +'<div class="brush-visual"><img src="./assets/brush.png" alt="Oclean X" class="brush-img"></div>'
    +'<div class="brush-data">'
    +'<div class="brush-batt"><div class="card-label">Batería</div><div class="batt-row"><div class="batt-bar"><div class="batt-fill'+(store.battery!=null?(store.battery<=20?' low':(store.battery<=50?' mid':'')):'')+'" style="width:'+(store.battery||0)+'%"></div></div><span class="batt-pct">'+(store.battery!=null?store.battery+'%':'—')+'</span></div></div>'
    +'<div class="brush-head"><div class="card-label">Cabezal</div><div class="head-days">'
    +(store.headDays!=null?('quedan <b>'+Math.max(0,(store.headDays-(store.headTimes||0)))+'</b> días'):'—')
    +'</div></div>'
    +'</div></div>';
  h+='<div class="connect-zone">'
    +'<button class="ui-button big" id="btn-sync" '+(state.connecting?'disabled':'')+'>'+(state.connecting?'Conectando…':'🔄 Sincronizar')+'</button>'
    +'<div class="ble-status"><span class="ble-dot'+(state.statusKind?' '+state.statusKind:'')+'"></span><span id="ble-status-txt">'+esc(state.status||statusDefault())+'</span></div>'
    +(pend?'<div class="settings-note" style="text-align:center">⚙️ Cambios de ajustes pendientes: se enviarán al sincronizar.</div>':'')
    +(state.showAllDevices?'<button class="ui-button ghost" id="btn-sync-all" style="margin-top:10px">Buscar entre todos los dispositivos</button>':'')
    +'</div>';
  // Selector tipo lente con los cepillados de hoy
  var today=todaySessions();
  h+='<div class="card-label" style="margin:14px 4px 8px">Cepillados de hoy'+(today.length&&today[0].sample?' · ejemplo':'')+'</div>';
  if(today.length){
    if(state.sel==null||state.sel>=today.length) state.sel=0;
    h+='<div class="sess-dock" id="sess-dock">'
      +today.map(function(s,i){ return '<button class="sess-chip'+(i===state.sel?' on':'')+'" data-i="'+i+'"><b>'+fmtTime(s.ts)+'</b><span>'+(s.score!=null?s.score:'—')+'</span></button>'; }).join('')
      +'<span class="sess-hl" id="sess-hl"></span></div>'
      +'<div id="sess-detail">'+sessDetail(today[state.sel])+'</div>';
  } else if(store.lastSync && store.lastSess===0){
    h+='<div class="mg-card empty-state"><span class="e-ico">🦷</span>No había sesiones nuevas en el cepillo.<br>Es normal: si la app oficial de Oclean se conectó antes, descargó el historial ella.<br>Cepíllate y sincroniza de nuevo aquí.</div>';
  } else {
    h+='<div class="mg-card empty-state"><span class="e-ico">🦷</span>Aún no hay cepillados hoy.<br>Conecta el cepillo para descargar tu historial.</div>';
  }
  return h;
}
function statusDefault(){
  if(store.lastSync){
    var base='Última sincronización: '+dayLabel(store.lastSync)+' · '+fmtTime(store.lastSync);
    if(store.lastSess===0) return base+' · sin sesiones nuevas en el cepillo';
    if(store.lastSess>0) return base+' · '+store.lastSess+(store.lastSess===1?' nueva':' nuevas');
    return base;
  }
  return 'Cepillo sin conectar';
}

function scoreRing(score,size){
  var sw=Math.max(3,Math.round(size*0.09)); // grosor proporcional: anillo fino en tarjetas
  var r=(size-sw-4)/2, c=2*Math.PI*r, val=score==null?0:score;
  var off=c*(1-val/100);
  var fs=Math.min(24,Math.round(size*0.36));
  return '<span class="score-ring '+scoreClass(score)+'" style="width:'+size+'px;height:'+size+'px">'
    +'<svg width="'+size+'" height="'+size+'"><circle class="ring-bg" cx="'+size/2+'" cy="'+size/2+'" r="'+r+'" fill="none" stroke-width="'+sw+'"/>'
    +'<circle class="ring-fg" cx="'+size/2+'" cy="'+size/2+'" r="'+r+'" fill="none" stroke-width="'+sw+'" stroke-dasharray="'+c.toFixed(1)+'" stroke-dashoffset="'+off.toFixed(1)+'"/></svg>'
    +'<span class="score-val" style="font-size:'+fs+'px">'+(score==null?'—':score)+'</span></span>';
}

function viewHistorial(){
  var src2=store.sessions;
  if(!src2.length){
    var sm=sampleSessions();
    return '<div class="card-label" style="margin:2px 4px 8px">Historial · ejemplo</div>'+dayCard(dayKey(sm[0].ts),sm,true)
      +'<div class="settings-note" style="text-align:center">Cuando sincronices el cepillo verás aquí tus días reales.</div>';
  }
  var days={};
  src2.forEach(function(s){ var k=dayKey(s.ts); (days[k]=days[k]||[]).push(s); });
  var keys=Object.keys(days).sort().reverse();
  return keys.map(function(k){ return dayCard(k,days[k],false); }).join('');
}
function dayCard(k,list,isSample){
  var avg=null,sum=0,n=0;
  list.forEach(function(s){ if(s.score!=null){sum+=s.score;n++;} });
  if(n) avg=Math.round(sum/n);
  var h='<div class="mg-card day-card"><div class="day-head2"><b>'+dayLabel(list[0].ts)+'</b>'
    +'<span class="day-meta">'+list.length+(list.length===1?' cepillado':' cepillados')+(avg!=null?' · media '+avg:'')+'</span></div>'
    +list.map(function(s){
      return '<button class="sess-row2" data-ts="'+s.ts+'">'+scoreRing(s.score,44)
        +'<span class="sr-main"><b>'+esc(schemeName(s.pnum))+'</b><span class="sr-sub">'+fmtTime(s.ts)+' · ⏱ '+fmtDur(s.dur)+' · Cobertura '+(s.coverage!=null?s.coverage+'%':'—')+'</span></span>'
        +'<span class="sr-chev">›</span></button>';
    }).join('')+'</div>';
  return h;
}

function viewAjustes(){
  var pend=store.pending||{};
  var curMode=(pend.scheme!=null?pend.scheme:store.brushMode);
  var opts='';
  Object.keys(SCHEMES).forEach(function(k){
    opts+='<option value="'+k+'"'+(String(k)===String(curMode)?' selected':'')+'>'+SCHEMES[k][0]+'</option>';
  });
  var modePh=(curMode==null?'<option value="" selected disabled>Desconocido (sincroniza)</option>':'');
  function tgl(id,cur,label){
    var on=(pend[id]!=null?pend[id]:cur);
    return '<div class="settings-row"><span>'+label+'</span>'
      +'<button class="ui-toggle'+(on?' on':'')+'" id="opt-'+id+'" role="switch" aria-checked="'+(!!on)+'"><span class="knob"></span></button></div>';
  }
  return '<div class="mg-tab"><div class="mg-settings">'
    +'<details class="settings-sec"><summary>Opciones de cepillado'+(Object.keys(pend).length?'<span class="pend-dot" title="cambios pendientes"></span>':'')+'</summary><div class="mg-card">'
    +'<div class="settings-row"><span>Modo de cepillado</span><select id="opt-mode" class="ui-select">'+modePh+opts+'</select></div>'
    +tgl('areaRemind',store.areaRemind,'Aviso de zonas')
    +tgl('remindSwitch',null,'Aviso de tiempo')
    +tgl('overPressure',store.overPressure,'Alerta de presión')
    +'<div class="settings-row"><span>Días de vida del cabezal</span><span class="inline-ctl"><input id="opt-head-days" class="ui-input" type="number" min="1" max="365" value="'+(store.headDays||90)+'"><button class="ui-button ghost" id="opt-head-apply">Aplicar</button></span></div>'
    +'<div class="settings-row"><span>Reiniciar contador de cabezal</span><button class="ui-button ghost" id="opt-head-reset">Reiniciar</button></div>'
    +'<div class="settings-note">Los cambios se envían al cepillo en la próxima sincronización. Potencia y duración vienen definidas por el modo elegido.</div>'
    +'</div></details>'
    +'<details class="settings-sec"><summary>Datos</summary><div class="mg-card">'
    +'<div class="settings-row"><span>Exportar historial</span><button class="ui-button ghost" id="btn-export">Exportar</button></div>'
    +'<div class="settings-row"><span>Restaurar historial</span><button class="ui-button ghost" id="btn-import">Elegir archivo</button></div>'
    +'<div class="settings-row"><span>Borrar todo</span><button class="ui-button ghost" id="btn-wipe" style="color:var(--ds-red)">Borrar</button></div>'
    +'</div></details>'
    +'<details class="settings-sec"><summary>Cepillo</summary><div class="mg-card">'
    +'<div class="settings-row"><span>Modelo</span><b>'+esc(store.model||'—')+'</b></div>'
    +'<div class="settings-note">Si usas también la app oficial de Oclean, sincroniza primero aquí: la oficial puede vaciar la memoria del cepillo al conectar.</div>'
    +'</div></details>'
    +'<details class="settings-sec"><summary>Diagnóstico</summary><div class="mg-card">'
    +'<pre class="diag-log" id="diag-log"></pre>'
    +'<div class="settings-row"><span>Registro de conexión</span><button class="ui-button ghost" id="btn-copy-log">Copiar</button></div>'
    +'<div class="settings-note">Si algo no funciona, copia este registro y envíaselo a Instinct.</div>'
    +'</div></details>'
    +'<div class="version-foot">Oclean · v'+APP_VERSION+'</div>'
    +'<div class="version-foot" style="font-size:10px;opacity:.55">Modelo 3D: BodyParts3D / Anatomography © DBCLS, adaptado por OrganUI y aquí (raíces recortadas, boca abierta, colores) · <a href="https://creativecommons.org/licenses/by-sa/2.1/jp/deed.es" target="_blank" rel="noopener" style="color:inherit">CC BY-SA 2.1 JP</a></div>'
    +'</div></div>';
}

/* ---------- Hoja de detalle ---------- */
function renderSheet(){
  var s=state.sheet; if(!s) return;
  var app=document.querySelector('.mg-app');
  var bd=document.createElement('div'); bd.className='mg-backdrop';
  var sh=document.createElement('div'); sh.className='mg-sheet';
  var zonesHtml='';
  if(s.zones && s.zones.some(function(v){return v>0;})){
    var max=Math.max.apply(null,s.zones.concat([1]));
    zonesHtml='<div class="zones">'+s.zones.map(function(v,i){
      return '<div class="zone'+(v===0?' off':'')+'"><div class="zbar"><div class="zfill" style="width:'+Math.round(v/max*100)+'%"></div></div><div class="zname">'+ZONES[i]+'</div></div>';
    }).join('')+'</div>';
  }
  var zc=zoneClasses(s);
  var dentureHtml=zc?'<div class="denture-wrap sheet"><canvas class="denture3d" data-live="1" data-zones=\''+JSON.stringify(zc)+'\'></canvas></div>':'';
  sh.innerHTML='<button class="sheet-x ui-close">✕</button>'
    +'<div class="sheet-title">'+esc(schemeName(s.pnum))+'</div>'
    +'<div class="sheet-when">'+dayLabel(s.ts)+' · '+fmtTime(s.ts)+'</div>'
    +scoreRing(s.score,86)
    +'<div style="text-align:center;font-size:14px;color:var(--ds-ink-2);margin:8px 0 4px">⏱ '+fmtDur(s.dur)
    +(s.durSched&&s.dur!==s.durSched?' de '+fmtDur(s.durSched):'')
    +' · Cobertura '+(s.coverage!=null? s.coverage+'%':'—')+'</div>'
    +dentureHtml+zonesHtml;
  app.appendChild(bd); app.appendChild(sh);
  requestAnimationFrame(function(){ bd.classList.add('show'); sh.classList.add('show'); });
  mountDentures();
  function close(){ state.sheet=null; render(); }
  bd.addEventListener('click',close);
  sh.querySelector('.sheet-x').addEventListener('click',close);
}

/* ---------- Cableado ---------- */
function wire(){
  document.querySelectorAll('.mg-tabs button').forEach(function(b){
    b.addEventListener('click',function(){ state.tab=b.dataset.tab; state.sheet=null; render(); });
  });
  document.querySelectorAll('.sess-row2').forEach(function(b){
    b.addEventListener('click',function(){
      var ts=+b.dataset.ts;
      var s=store.sessions.find(function(x){return x.ts===ts;})||sampleSessions().find(function(x){return x.ts===ts;});
      if(s){ state.sheet=s; render(); }
    });
  });
  var dock=document.getElementById('sess-dock');
  if(dock){
    var hl=document.getElementById('sess-hl');
    var chips=Array.prototype.slice.call(dock.querySelectorAll('.sess-chip'));
    var placeHl=function(){ var on=dock.querySelector('.sess-chip.on'); if(on&&hl){ hl.style.left=on.offsetLeft+'px'; hl.style.width=on.offsetWidth+'px'; } };
    var selectChip=function(b){
      chips.forEach(function(x){ x.classList.remove('on'); });
      b.classList.add('on'); placeHl();
      var i=+b.dataset.i; state.sel=i;
      var det=document.getElementById('sess-detail');
      if(det){ det.innerHTML=sessDetail(todaySessions()[i]); if(window.Denture3D){ window.Denture3D.disposeAll(); mountDentures(); } }
    };
    placeHl();
    window.addEventListener('resize',placeHl);
    chips.forEach(function(b){
      b.addEventListener('click',function(){ if(dock.dataset.dragged) return; selectChip(b); });
    });
    /* Lente roja arrastrable con el dedo, como la lente del dock */
    var drag=null;
    var chipAt=function(x){
      var best=null,bd=1e9;
      chips.forEach(function(b){ var r=b.getBoundingClientRect(); var d=Math.abs(x-(r.left+r.width/2)); if(d<bd){bd=d;best=b;} });
      return best;
    };
    dock.addEventListener('pointerdown',function(e){
      if(!e.isPrimary||e.button!==0) return;
      drag={id:e.pointerId,x0:e.clientX,l0:parseFloat(hl.style.left)||chips[0].offsetLeft,moved:false};
    });
    dock.addEventListener('pointermove',function(e){
      if(!drag||e.pointerId!==drag.id) return;
      var dx=e.clientX-drag.x0;
      if(!drag.moved&&Math.abs(dx)>6){ drag.moved=true; try{dock.setPointerCapture(e.pointerId);}catch(err){} hl.style.transition='none'; }
      if(!drag.moved) return;
      if(e.cancelable) e.preventDefault();
      var minL=chips[0].offsetLeft, maxL=chips[chips.length-1].offsetLeft;
      var nl=drag.l0+dx;
      if(nl<minL) nl=minL+(nl-minL)*.35;
      if(nl>maxL) nl=maxL+(nl-maxL)*.35;
      hl.style.left=nl+'px';
      var over=chipAt(e.clientX);
      if(over) chips.forEach(function(x){ x.classList.toggle('on',x===over); });
    });
    var endDrag=function(e){
      if(!drag||e.pointerId!==drag.id) return;
      var moved=drag.moved; drag=null;
      hl.style.transition='';
      if(!moved) return;
      dock.dataset.dragged='1';
      setTimeout(function(){ delete dock.dataset.dragged; },80);
      var over=chipAt(e.clientX);
      if(over) selectChip(over); else placeHl();
    };
    dock.addEventListener('pointerup',endDrag);
    dock.addEventListener('pointercancel',endDrag);
  }
  var bs=document.getElementById('btn-sync'); if(bs) bs.addEventListener('click',function(){ sync(false); });
  var ba=document.getElementById('btn-sync-all'); if(ba) ba.addEventListener('click',function(){ sync(true); });
  var ex=document.getElementById('btn-export'); if(ex) ex.addEventListener('click',doExport);
  // Acordeones de Ajustes con apertura fluida (una sola animación a la vez)
  document.querySelectorAll('details.settings-sec').forEach(function(d){
    var sum=d.querySelector('summary');
    if(!sum||sum.dataset.fluid) return;
    sum.dataset.fluid='1';
    var anim=null;
    sum.addEventListener('click',function(e){
      e.preventDefault();
      var content=d.querySelector(':scope > div');
      if(!content){ d.open=!d.open; return; }
      var startH=content.getBoundingClientRect().height;
      if(anim){ anim.cancel(); anim=null; } // no apilar: retoma desde la altura actual
      var opening=!d.open;
      content.style.overflow='hidden';
      if(opening){
        d.open=true;
        var endH=content.offsetHeight;
        anim=content.animate(
          [{height:startH+'px',opacity:startH>0?1:0},{height:endH+'px',opacity:1}],
          {duration:340,easing:'cubic-bezier(.34,1.25,.64,1)'}); // rebote suave Jelly
        anim.onfinish=function(){ content.style.overflow=''; anim=null; };
      }else{
        anim=content.animate(
          [{height:startH+'px',opacity:1},{height:'0px',opacity:0}],
          {duration:240,easing:'cubic-bezier(.4,0,.2,1)'});
        anim.onfinish=function(){ d.open=false; content.style.overflow=''; anim=null; };
      }
    });
  });
  var im=document.getElementById('btn-import'); if(im) im.addEventListener('click',doImport);
  var wp=document.getElementById('btn-wipe'); if(wp) wp.addEventListener('click',doWipe);
  var dl=document.getElementById('diag-log'); if(dl) dl.textContent=diag.join('\n')||'(vacío)';
  var cl=document.getElementById('btn-copy-log'); if(cl) cl.addEventListener('click',function(){
    var txt=diag.join('\n');
    function done(){ toast('Registro copiado'); }
    if(navigator.clipboard && navigator.clipboard.writeText){ navigator.clipboard.writeText(txt).then(done,function(){ fallbackCopy(); }); }
    else fallbackCopy();
    function fallbackCopy(){ var ta=document.createElement('textarea'); ta.value=txt; document.body.appendChild(ta); ta.select(); try{ document.execCommand('copy'); done(); }catch(e){ toast('No se pudo copiar'); } document.body.removeChild(ta); }
  });
  function setPend(k,v){ store.pending=store.pending||{}; store.pending[k]=v; save(); toast('Se aplicará en la próxima sincronización'); }
  var om=document.getElementById('opt-mode');
  if(om) om.addEventListener('change',function(){ setPend('scheme',parseInt(om.value,10)); });
  ['areaRemind','remindSwitch','overPressure'].forEach(function(id){
    var b=document.getElementById('opt-'+id);
    if(b) b.addEventListener('click',function(){
      var on=b.getAttribute('aria-checked')!=='true';
      b.setAttribute('aria-checked',String(on)); b.classList.toggle('on',on);
      setPend(id,on);
    });
  });
  var ha=document.getElementById('opt-head-apply');
  if(ha) ha.addEventListener('click',function(){
    var v=parseInt((document.getElementById('opt-head-days')||{}).value,10);
    if(v>0&&v<366) setPend('headMaxDays',v); else toast('Días no válidos');
  });
  var hr=document.getElementById('opt-head-reset');
  if(hr) hr.addEventListener('click',function(){ setPend('resetHead',true); });
  var up=document.getElementById('update-pill');
  if(up){ up.addEventListener('click',function(){ location.reload(); }); if(updateAvailable) up.hidden=false; }
}

function doExport(){
  var blob=new Blob([JSON.stringify(store.sessions,null,1)],{type:'application/json'});
  var a=document.createElement('a'); a.href=URL.createObjectURL(blob);
  a.download='mi-cepillo-historial.json'; a.click();
  setTimeout(function(){ URL.revokeObjectURL(a.href); },4000);
  toast('Historial exportado');
}
function doImport(){
  var inp=document.createElement('input'); inp.type='file'; inp.accept='application/json,.json';
  inp.addEventListener('change',function(){
    var f=inp.files[0]; if(!f) return;
    var rd=new FileReader();
    rd.onload=function(){
      try{
        var arr=JSON.parse(rd.result);
        if(!Array.isArray(arr)) throw 0;
        var n=0;
        arr.forEach(function(s){ if(s && s.ts && mergeSession(s)) n++; });
        sortSessions(); save(); render();
        toast('Historial restaurado ('+n+' nuevos)');
      }catch(e){ toast('Ese archivo no vale'); }
    };
    rd.readAsText(f);
  });
  inp.click();
}
var wipeArmed=false;
function doWipe(){
  if(!wipeArmed){ wipeArmed=true; toast('Pulsa Borrar otra vez para confirmar'); setTimeout(function(){wipeArmed=false;},3000); return; }
  store={sessions:[],battery:null,headTimes:null,headDays:null,model:null,lastSync:null,lastSess:null,brushMode:null,areaRemind:null,overPressure:null,pending:{}};
  save(); render(); toast('Datos borrados');
}

/* ================================================================
   BLE — protocolo Oclean Type-1 (OCLEANY3M)
   ================================================================ */
function sleep(ms){ return new Promise(function(r){ setTimeout(r,ms); }); }
function tzIndex(){
  var off=-new Date().getTimezoneOffset(); // minutos respecto a UTC
  var best=0;
  for(var i=1;i<TZ_MIN.length;i++) if(Math.abs(TZ_MIN[i]-off)<Math.abs(TZ_MIN[best]-off)) best=i;
  return best+1; // 1-based
}

function parseSessionRecord(r){
  // Registro de 42 bytes (C3385w0 / OCLEANY3M)
  if(r.length<42) return null;
  var year=r[0]+2000;
  if(year<2020) return null;
  var ts=new Date(year,r[1]-1,r[2],r[3],r[4],r[5]).getTime();
  if(!isFinite(ts)) return null;
  var sched=(r[7]<<8)|r[8], valid=(r[9]<<8)|r[10];
  var dur=null;
  if(valid>0 && (sched===0||valid<=sched)) dur=valid; else if(sched>0) dur=sched;
  var score=r[33]; if(!(score>0&&score<=100)) score=null;
  var zones=[r[23],r[24],r[25],r[26],r[27],r[28],r[29],r[30]];
  var total=zones.reduce(function(a,b){return a+b;},0), coverage=null;
  if(total>0 && sched>0){
    var thr=9/sched, covered=0;
    zones.forEach(function(v){ if(v/total>=thr) covered++; });
    coverage=Math.round(covered/8*100);
  }
  return { ts:ts, pnum:r[6], dur:dur, durSched:sched>0?sched:null, score:score,
           zones:zones.some(function(v){return v>0;})?zones:null, coverage:coverage };
}

function mergeSession(s){
  if(!s||!s.ts) return false;
  var ex=store.sessions.find(function(x){return x.ts===s.ts;});
  if(!ex){ store.sessions.push(s); return true; }
  var changed=false;
  ['pnum','dur','durSched','score','zones','coverage'].forEach(function(k){
    if(s[k]!=null && ex[k]==null){ ex[k]=s[k]; changed=true; }
    else if(k==='score' && s.score!=null){ ex.score=s.score; changed=true; }
  });
  return changed;
}
function sortSessions(){ store.sessions.sort(function(a,b){return b.ts-a.ts;}); }
function newestSession(){ return store.sessions[0]||null; }

async function sync(acceptAll){
  if(state.connecting) return;
  if(!navigator.bluetooth){ toast('Safari no trae Bluetooth: activa la extensión beacio (iOS 26.2+) o abre la app en Bluefy'); return; }
  state.connecting=true; state.statusKind='busy'; state.status='Buscando el cepillo…'; render();
  dlog('--- sync start v'+APP_VERSION+' (acceptAll='+acceptAll+') ---');
  dlog('backend BLE: '+(window.BleClient?'BleClient(wrapper oficial)':(window.Capacitor&&window.Capacitor.Plugins?(Object.keys(window.Capacitor.Plugins).join(',')||'sin plugins'):'sin Capacitor')));
  var device=null;
  try{
    var opts={ optionalServices:[SVC,BATT_SVC,DIS_SVC] };
    if(acceptAll) opts.acceptAllDevices=true; else opts.filters=[{services:[SVC]},{namePrefix:'Oclean'}];
    device=await navigator.bluetooth.requestDevice(opts);
    dlog('requestDevice OK: '+(device.name||'(sin nombre)'));
  }catch(e){
    dlog('requestDevice error: '+(e&&e.name)+' '+(e&&e.message));
    state.connecting=false; state.statusKind=''; state.status='Sin conexión';
    if(e && e.name==='NotFoundError'){
      if(!acceptAll){ state.showAllDevices=true; state.status='No apareció. Despierta el cepillo (levántalo) y reintenta'; }
      else state.status='No se encontró. Acércalo encendido y reintenta';
    } else { state.status='No se pudo abrir Bluetooth'; }
    render(); return;
  }
  state.showAllDevices=false;
  await finishSync(device);
}

async function finishSync(device){
  try{
    await runSync(device);
    if(store.lastSess===0){ state.status='Sincronizado · sin sesiones nuevas en el cepillo'; }
    else if(store.lastSess>0){ state.status='Sincronizado · '+store.lastSess+(store.lastSess===1?' sesión nueva':' sesiones nuevas'); }
    else { state.status='Sincronizado · '+fmtTime(Date.now()); }
    state.statusKind='on';
    toast(store.lastSess===0 ? 'Sin sesiones nuevas en el cepillo' : 'Sincronización completa ✨');
  }catch(e){
    state.status='Falló la sincronización. Reintenta con el cepillo cerca';
    state.statusKind='';
    toast('No se pudo sincronizar');
  }
  state.connecting=false; render();
}

/* ---------- Sincronización automática al abrir ----------
   Web Bluetooth exige gesto del usuario para requestDevice(); lo que sí se puede
   sin gesto es reconectar a un aparato ya autorizado (getDevices). Si no hay
   aparato autorizado, el primer toque en la página lanza la sincronización. */
var tapSyncArmed=false;
function armTapSync(){
  if(tapSyncArmed) return; tapSyncArmed=true;
  var h=function(){
    document.removeEventListener('pointerdown',h,true);
    if(state.connecting) return;
    dlog('autosync: primer toque -> sync');
    sync(false);
  };
  document.addEventListener('pointerdown',h,true);
}
async function autoSyncOnLoad(){
  if(state.connecting) return;
  if(!navigator.bluetooth) return; // sin BLE no hay autosync ni aviso fijo
  if(!navigator.bluetooth.getDevices){ dlog('autosync: sin getDevices, armo primer toque'); armTapSync(); return; }
  var devs=[];
  try{ devs=await navigator.bluetooth.getDevices(); }catch(e){ dlog('autosync getDevices error: '+(e&&e.message)); }
  if(!devs||!devs.length){ dlog('autosync: ningún aparato autorizado, armo primer toque'); armTapSync(); return; }
  dlog('autosync: getDevices devuelve '+devs.length+', reconectando');
  state.connecting=true; state.statusKind='busy'; state.status='Reconectando con el cepillo…'; render();
  await finishSync(devs[0]);
}

async function runSync(device){
  store.lastSync=Date.now(); save();
  var sessFetched=0;
  var server=device.gatt;
  await server.connect();
  dlog('GATT conectado');
  try{
    await sleep(2000); // calentamiento GATT (como la integración de referencia)
    var svc=await server.getPrimaryService(SVC);
    var chWrite=await svc.getCharacteristic(C_WRITE);
    var chSend =await svc.getCharacteristic(C_SEND);
    var chNotify=null, chRecv=null;
    try{ chNotify=await svc.getCharacteristic(C_NOTIFY); }catch(e){ dlog('getCharacteristic fbb86 error: '+e.message); }
    try{ chRecv  =await svc.getCharacteristic(C_RECV);  }catch(e){ dlog('getCharacteristic fbb90 error: '+e.message); }

    // Inventario del servicio: qué características hay y con qué propiedades
    function propStr(c){ var p=c.properties; return [p.read?'read':'',p.write?'write':'',p.writeWithoutResponse?'writeNoRsp':'',p.notify?'notify':'',p.indicate?'indicate':''].filter(Boolean).join('+')||'(ninguna)'; }
    try{
      var allCh=await svc.getCharacteristics();
      for(var ci=0;ci<allCh.length;ci++){ dlog('char ...'+allCh[ci].uuid.slice(-5)+' props: '+propStr(allCh[ci])); }
    }catch(e){ dlog('getCharacteristics error: '+e.message); }

    // Estado de la recogida
    var sessEvent=null, sessResolve=null;
    sessEvent=new Promise(function(r){ sessResolve=r; });
    var t1={active:false, buf:[], expected:0};

    function u8(v){ return new Uint8Array(v.buffer, v.byteOffset, v.byteLength); }
    function onNotify86(ev){ var d=u8(ev.target.value); dlog('notif fbb86 ['+d.length+'B]: '+hex(d)); dispatch(d, false); }
    function onNotify90(ev){ var d=u8(ev.target.value); dlog('notif fbb90 ['+d.length+'B]: '+hex(d)); dispatch(d, true); }

    var lastHex={f86:'',f90:''};
    function dispatch(d, isRecv){
      // Continuación *B# (solo en fbb90): todo paquete es continuación mientras dure
      if(isRecv && t1.active){
        for(var i=0;i<d.length;i++) t1.buf.push(d[i]);
        if(t1.buf.length>=t1.expected){ flushT1(); }
        return;
      }
      var h=hex(d), key=isRecv?'f90':'f86';
      if(h===lastHex[key]){ dlog('duplicado descartado en '+key); return; }
      lastHex[key]=h;
      if(d.length<2) return;
      var prefix=(d[0]<<8)|d[1];
      var p=Array.from(d.slice(2));
      if(prefix===0x0307 && d.length>=8 && d[2]===0x2a && d[3]===0x42 && d[4]===0x23){
        // Cabecera *B#: count (2 BE) + datos en línea
        var count=(d[5]<<8)|d[6];
        var inline=Array.from(d.slice(7));
        dlog('*B# cabecera: count='+count+', inline='+inline.length+'B');
        if(count>0){
          t1.active=true; t1.buf=inline; t1.expected=count*42;
          if(t1.buf.length>=t1.expected) flushT1();
        } else if(inline.length>=11){
          // Modo en línea: año..s, pNum, duración(2), válida(2) del último registro
          var y0=inline[0]+2000;
          if(y0>=2020){
            var ts0=new Date(y0,inline[1]-1,inline[2],inline[3],inline[4],inline[5]).getTime();
            var sched0=(inline[7]<<8)|inline[8], valid0=(inline[9]<<8)|inline[10];
            var dur0=null;
            if(valid0>0 && (sched0===0||valid0<=sched0)) dur0=valid0; else if(sched0>0) dur0=sched0;
            if(mergeSession({ts:ts0,pnum:inline[6],dur:dur0,durSched:sched0>0?sched0:null})) sessFetched++;
            sortSessions(); sessResolve();
          }
        } else { dlog('buffer vacío: el cepillo no tiene sesiones guardadas (¿la app oficial las descargó antes?)'); }
        return;
      }
      if(prefix===0x0303){ // estado: batería en payload[3]
        if(p.length>=4 && p[3]>=0 && p[3]<=100) store.battery=p[3];
        return;
      }
      if(prefix===0x0302){ // ajustes: batería payload[0], modo payload[5], avisos payload[8]/[23], cabezal payload[29..31]
        if(p.length>=1 && p[0]<=100) store.battery=p[0];
        if(p.length>=32){
          store.headDays=(p[29]<<8)|p[30];
          store.headTimes=p[31];
          store.brushMode=p[5]; store.overPressure=!!p[8]; store.areaRemind=!!p[23];
        }
        return;
      }
      if(prefix===0x0000){ // push de puntuación
        if(p.length>=1 && p[0]!==0xff && p[0]<=100){
          var s=newestSession(); if(s){ s.score=p[0]; }
        }
        return;
      }
      if(prefix===0x2604){ // push de zonas
        if(p.length>=14){
          var areas=p.slice(6,14);
          var s2=newestSession();
          if(s2){
            s2.zones=areas;
            var cov=areas.filter(function(v){return v>100;}).length;
            s2.coverage=Math.round(cov/8*100);
          }
        }
        return;
      }
      if(prefix===0x5a00){ // metadatos de sesión
        if(p.length>=18){
          var y=p[7]+2000;
          if(y>=2020){
            var ts=new Date(y,p[8]-1,p[9],p[10],p[11],p[12]).getTime();
            var dur=p[15]!==0xff?p[15]:null;
            if(mergeSession({ts:ts,pnum:null,dur:dur})){ sortSessions(); }
            sessResolve();
          }
        }
        return;
      }
      if(prefix===0x0308){ // respuesta INFO (registros simples/extendidos, por si acaso)
        var rec2=parseSessionRecord(new Uint8Array(p));
        if(rec2){ mergeSession(rec2); sortSessions(); sessResolve(); }
        return;
      }
    }

    function flushT1(){
      var buf=new Uint8Array(t1.buf);
      t1.active=false; t1.buf=[]; t1.expected=0;
      var n=Math.floor(buf.length/42);
      dlog('*B# reensamblado: '+buf.length+'B = '+n+' registro(s)');
      for(var i=0;i<n;i++){
        var rec=parseSessionRecord(buf.slice(i*42,(i+1)*42));
        if(rec){ mergeSession(rec); sessResolve(); sessFetched++; dlog('  registro '+i+': ts='+new Date(rec.ts).toLocaleString('es-ES')+' pNum='+rec.pnum+' dur='+rec.dur+' score='+rec.score); }
        else dlog('  registro '+i+': no parseable');
      }
      sortSessions();
    }

    // 0) Suscripciones y sondas (antes de cualquier escritura)
    var subOk=false;
    var pollChars=[];
    async function sub(ch,name,handler,allowPoll){
      if(!ch) return false;
      var p=ch.properties;
      if(!p.notify && !p.indicate){ dlog('subscribe '+name+': sin propiedad notify/indicate ('+propStr(ch)+')'); }
      else {
        try{ await ch.startNotifications(); ch.addEventListener('characteristicvaluechanged',handler); dlog('subscribe '+name+' OK'); return true; }
        catch(e){
          dlog('subscribe '+name+' error: '+(e&&e.name)+': '+e.message);
          try{
            if(typeof ch.getDescriptor!=='function') throw new Error('sin getDescriptor en este backend');
            var cccd=await ch.getDescriptor('00002902-0000-1000-8000-00805f9b34fb');
            await cccd.writeValue(new Uint8Array([1,0]));
            ch.addEventListener('characteristicvaluechanged',handler);
            dlog('subscribe '+name+' OK via CCCD manual'); return true;
          }catch(e2){ dlog('CCCD manual '+name+' no disponible: '+(e2&&e2.message)); }
        }
      }
      if(allowPoll!==false && p.read){ pollChars.push({ch:ch,name:name}); dlog(name+': usaré lectura por sondeo como respaldo'); }
      return false;
    }
    if(await sub(chNotify,'fbb86',onNotify86)) subOk=true;
    if(await sub(chRecv,'fbb90',onNotify90)) subOk=true;
    // Sondas discriminadoras: bateria estandar y otras caracteristicas notify del servicio
    try{
      var bs0=await server.getPrimaryService(BATT_SVC);
      var bc0=await bs0.getCharacteristic(BATT_CHAR);
      dlog('char 2a19 props: '+propStr(bc0));
      if(await sub(bc0,'2a19',function(ev){ var d=u8(ev.target.value); dlog('notif 2a19 ['+d.length+'B]: '+hex(d)); },false)) subOk=true;
    }catch(e){ dlog('sonda 2a19 error: '+(e&&e.name)+': '+(e&&e.message)); }
    if(typeof allCh!=='undefined' && allCh){
      for(var ci2=0; ci2<allCh.length; ci2++){
        var xc=allCh[ci2];
        if(xc.uuid!==C_NOTIFY && xc.uuid!==C_RECV && (xc.properties.notify||xc.properties.indicate)){
          var xn='...'+xc.uuid.slice(-5);
          if(await sub(xc,xn,(function(nm){ return function(ev){ var d=u8(ev.target.value); dlog('notif '+nm+' ['+d.length+'B]: '+hex(d)); }; })(xn),false)) subOk=true;
        }
      }
    }

    // 1) Calibración de hora (Type-1: 0201 + 8 bytes, por fbb85)
    var now=new Date();
    var cal=new Uint8Array([0x02,0x01, now.getFullYear()-2000, now.getMonth()+1, now.getDate(),
      now.getHours(), now.getMinutes(), now.getSeconds(), (now.getDay())%7, tzIndex()]);
    try{ await chWrite.writeValueWithResponse(cal); dlog('calibración hora OK -> fbb85: '+hex(cal)); }catch(e){ dlog('calibración error: '+e.message); }

    // 2) Modelo (DIS), solo informativo
    try{
      var dis=await server.getPrimaryService(DIS_SVC);
      var mc=await dis.getCharacteristic(DIS_MODEL);
      var mv=await mc.readValue();
      store.model=new TextDecoder().decode(mv).replace(/\0.*$/,'');
      dlog('modelo DIS: '+store.model);
    }catch(e){ dlog('DIS error: '+e.message); }


    // 4) Comandos por fbb89
    async function cmd(bytes){ try{ await chSend.writeValueWithResponse(new Uint8Array(bytes)); dlog('cmd '+hex(new Uint8Array(bytes))+' -> fbb89 OK'); }catch(e){ dlog('cmd '+hex(new Uint8Array(bytes))+' error: '+e.message); } await sleep(150); }
    await cmd([0x03,0x03]);       // estado (batería)
    await cmd([0x03,0x02,0x01]);  // ajustes (cabezal)
    await cmd([0x03,0x07]);       // sesiones (*B# por fbb90)

    // 4c) Ajustes pendientes del usuario (escrituras standalone -> fbb85)
    var pend=store.pending||{};
    if(Object.keys(pend).length){
      dlog('aplicando ajustes pendientes: '+JSON.stringify(pend));
      async function w85(bytes,label){
        try{ await chWrite.writeValueWithResponse(new Uint8Array(bytes)); dlog('write '+label+' -> fbb85 OK: '+hex(new Uint8Array(bytes))); return true; }
        catch(e){ dlog('write '+label+' error: '+(e&&e.name)+': '+e.message); return false; }
      }
      var allOk=true;
      if(pend.scheme!=null && SCHEMES[pend.scheme]){
        var pkts=buildSchemePackets(pend.scheme);
        for(var pi=0;pi<pkts.length;pi++){ if(!await w85(pkts[pi],'0206 modo '+pend.scheme)) allOk=false; await sleep(80); }
        if(allOk) store.brushMode=pend.scheme;
      }
      if(pend.areaRemind!=null){ if(!await w85([0x02,0x0d,pend.areaRemind?1:0],'020D aviso zonas')) allOk=false; else store.areaRemind=pend.areaRemind; }
      if(pend.remindSwitch!=null){ if(!await w85([0x02,0x39,pend.remindSwitch?1:0],'0239 aviso tiempo')) allOk=false; }
      if(pend.overPressure!=null){ if(!await w85([0x02,0x12,pend.overPressure?1:0],'0212 alerta presión')) allOk=false; else store.overPressure=pend.overPressure; }
      if(pend.headDays!=null){ var hd=Math.max(1,Math.min(365,pend.headDays|0)); if(!await w85([0x02,0x17,(hd>>8)&0xff,hd&0xff],'0217 días cabezal')) allOk=false; else store.headDays=hd; }
      if(pend.resetHead){ if(!await w85([0x02,0x0f],'020F reinicio cabezal')) allOk=false; else store.headTimes=0; }
      if(allOk){ store.pending={}; dlog('ajustes aplicados'); toast('Ajustes enviados al cepillo'); }
      else dlog('algunos ajustes no se pudieron enviar; quedan pendientes');
      save();
    }

    // 4b) Si no hay suscripción posible: sondeo por lectura (respaldo)
    for(var pr=0; pr<pollChars.length; pr++){
      var pc=pollChars[pr];
      for(var rd=0; rd<6; rd++){
        try{
          var pv=await pc.ch.readValue();
          var pd=u8(pv);
          if(pd.length){ dlog('sondeo '+pc.name+' ['+pd.length+'B]: '+hex(pd)); dispatch(pd, pc.name==='fbb90'); }
          else dlog('sondeo '+pc.name+': vacío');
        }catch(e){ dlog('sondeo '+pc.name+' error: '+e.message); break; }
        await sleep(400);
      }
    }

    dlog('estado antes de espera: subOk='+subOk+', sondeo='+pollChars.length+' char(s), batería='+store.battery+', cabezal='+store.headDays);
    // 5) Espera de sesiones y enriquecimiento
    try{ await Promise.race([sessEvent, sleep(subOk?8000:(pollChars.length?4000:3000))]); }catch(e){}
    if(t1.active) flushT1();
    store.lastSess=sessFetched;
    dlog('espera terminada; sesiones recibidas esta sync: '+sessFetched+'; en store: '+store.sessions.length);
    await sleep(1500); // pushes 0000 / 2604 / 5a00 llegan después

    // 6) Batería estándar BLE
    try{
      var bs=await server.getPrimaryService(BATT_SVC);
      var bc=await bs.getCharacteristic(BATT_CHAR);
      var bv=await bc.readValue();
      store.battery=bv.getUint8(0);
      dlog('batería 0x2A19: '+store.battery+'%');
    }catch(e){ dlog('batería 0x2A19 error: '+e.message); }

    sortSessions(); save();
    dlog('--- sync fin: '+store.sessions.length+' sesiones, batería '+store.battery+', cabezal '+store.headDays+' días, modelo '+(store.model||'?')+' ---');
  } finally {
    try{ server.disconnect(); }catch(e){}
  }
}

/* ---------- Aviso de nueva versión ---------- */
var updateAvailable=false;
function checkVersion(){
  fetch('./version.txt?t='+Date.now(),{cache:'no-store'}).then(function(r){
    if(!r.ok) return null; return r.text();
  }).then(function(t){
    if(t==null) return;
    updateAvailable=(t.trim()!==APP_VERSION);
    var pill=document.getElementById('update-pill');
    if(pill) pill.hidden=!updateAvailable;
  }).catch(function(){});
}
setInterval(checkVersion,60000);
document.addEventListener('visibilitychange',function(){ if(!document.hidden) checkVersion(); });

render();
checkVersion();
autoSyncOnLoad();
})();
