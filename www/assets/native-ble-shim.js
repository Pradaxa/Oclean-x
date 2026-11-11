/* Puente Web Bluetooth -> Capacitor BLE (solo app nativa).
   En la web normal este archivo no hace nada: window.Capacitor no existe.
   En la app nativa instala navigator.bluetooth con la forma de la Web
   Bluetooth API para que app.js funcione sin cambios.
   El plugin nativo puede tardar en registrarse en Capacitor.Plugins tras
   la carga de los scripts: por eso navigator.bluetooth se instala ya y el
   plugin se resuelve de forma perezosa en la primera llamada, con espera. */
(function(){
'use strict';
if(!(window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform())) return;

var Ble=null, bleWait=null, initDone=null;

function getBle(){
  var P=window.Capacitor.Plugins||{};
  return P.BleClient||null;
}
function waitBle(){
  if(Ble) return Promise.resolve(Ble);
  if(!bleWait){
    bleWait=new Promise(function(res,rej){
      var n=0;
      (function poll(){
        var b=getBle();
        if(b){ Ble=b; return res(b); }
        if(++n>120){ bleWait=null; return rej(new Error('plugin BLE nativo no disponible')); }
        setTimeout(poll,250);
      })();
    });
  }
  return bleWait;
}
function ensureInit(){
  return waitBle().then(function(b){
    if(!initDone) initDone=b.initialize();
    return initDone;
  });
}
function nativeBanner(msg){
  try{
    var d=document.getElementById('native-ble-warn');
    if(!d){
      d=document.createElement('div'); d.id='native-ble-warn';
      d.style.cssText='position:fixed;left:12px;right:12px;bottom:110px;z-index:99999;background:#7a1f1f;color:#fff;font:13px/1.4 -apple-system,sans-serif;padding:10px 12px;border-radius:12px;text-align:center';
      document.body.appendChild(d);
    }
    d.textContent=msg;
  }catch(e){}
}

function normUuid(u){
  if(typeof u==='number') u=u.toString(16);
  u=String(u).toLowerCase();
  if(/^[0-9a-f]{1,4}$/.test(u)) u='0000'+u.padStart(4,'0')+'-0000-1000-8000-00805f9b34bf';
  else if(/^[0-9a-f]{8}$/.test(u)) u=u+'-0000-1000-8000-00805f9b34bf';
  return u;
}
function toDataView(v){
  if(v instanceof DataView) return v;
  if(v instanceof ArrayBuffer) return new DataView(v);
  if(v && v.buffer) return new DataView(v.buffer, v.byteOffset||0, v.byteLength!==undefined?v.byteLength:v.length);
  return v;
}
function notFound(msg){ return new DOMException(msg||'No encontrado','NotFoundError'); }

/* ---------- Characteristic ---------- */
function ShimCharacteristic(deviceId, svcUuid, info){
  this._deviceId=deviceId;
  this._svc=normUuid(svcUuid);
  this.uuid=normUuid(info.uuid);
  this.properties=info.properties||{};
  this._listeners={};
}
ShimCharacteristic.prototype.addEventListener=function(type,fn){
  (this._listeners[type]=this._listeners[type]||[]).push(fn);
};
ShimCharacteristic.prototype.removeEventListener=function(type,fn){
  var a=this._listeners[type]||[]; var i=a.indexOf(fn); if(i>=0) a.splice(i,1);
};
ShimCharacteristic.prototype._emit=function(type,value){
  var ev={target:{value:value}};
  (this._listeners[type]||[]).slice().forEach(function(fn){ try{ fn(ev); }catch(e){ console.error(e); } });
};
ShimCharacteristic.prototype.startNotifications=async function(){
  var b=await waitBle(); var self=this;
  await b.startNotifications(this._deviceId,this._svc,this.uuid,function(value){
    self._emit('characteristicvaluechanged',toDataView(value));
  });
};
ShimCharacteristic.prototype.stopNotifications=async function(){
  var b=await waitBle();
  await b.stopNotifications(this._deviceId,this._svc,this.uuid);
};
ShimCharacteristic.prototype.readValue=async function(){
  var b=await waitBle();
  return toDataView(await b.read(this._deviceId,this._svc,this.uuid));
};
ShimCharacteristic.prototype.writeValue=async function(v){
  var b=await waitBle();
  await b.write(this._deviceId,this._svc,this.uuid,toDataView(v));
};
ShimCharacteristic.prototype.writeValueWithResponse=ShimCharacteristic.prototype.writeValue;
ShimCharacteristic.prototype.writeValueWithoutResponse=async function(v){
  var b=await waitBle();
  await b.writeWithoutResponse(this._deviceId,this._svc,this.uuid,toDataView(v));
};

/* ---------- Service ---------- */
function ShimService(deviceId,svc){
  this._deviceId=deviceId;
  this.uuid=normUuid(svc.uuid);
  this._chars={};
  var self=this;
  (svc.characteristics||[]).forEach(function(c){
    var sc=new ShimCharacteristic(deviceId,svc.uuid,c);
    self._chars[sc.uuid]=sc;
  });
}
ShimService.prototype.getCharacteristic=async function(u){
  var c=this._chars[normUuid(u)];
  if(!c) throw notFound('Caracteristica '+u+' no encontrada');
  return c;
};
ShimService.prototype.getCharacteristics=async function(){
  var self=this;
  return Object.keys(this._chars).map(function(k){ return self._chars[k]; });
};

/* ---------- Server / Device ---------- */
function ShimServer(device){
  this._dev=device;
  this.connected=false;
  this._services=null;
}
ShimServer.prototype.connect=async function(){
  var b=await waitBle();
  var self=this;
  await b.connect(this._dev.id,function(){ self.connected=false; });
  var services=await b.getServices(this._dev.id);
  this._services={};
  services.forEach(function(s){ self._services[normUuid(s.uuid)]=new ShimService(self._dev.id,s); });
  this.connected=true;
  return this;
};
ShimServer.prototype.getPrimaryService=async function(u){
  var s=this._services && this._services[normUuid(u)];
  if(!s) throw notFound('Servicio '+u+' no encontrado');
  return s;
};
ShimServer.prototype.disconnect=async function(){
  try{ var b=await waitBle(); await b.disconnect(this._dev.id); }catch(e){}
  this.connected=false;
};

function ShimDevice(id,name){
  this.id=id;
  this.name=name||'';
  this.gatt=new ShimServer(this);
}

/* ---------- navigator.bluetooth ---------- */
var bluetooth={
  requestDevice:async function(opts){
    await ensureInit();
    var b=await waitBle();
    opts=opts||{};
    var req={};
    var svcFilter=null, namePrefix=null, name=null;
    (opts.filters||[]).forEach(function(f){
      if(f.services && f.services.length && !svcFilter) svcFilter=f.services;
      if(f.namePrefix && !namePrefix) namePrefix=f.namePrefix;
      if(f.name && !name) name=f.name;
    });
    /* La web usa OR entre filtros; el plugin los combina como AND.
       Priorizamos servicio > nombre > prefijo para no quedarnos sin resultados. */
    if(svcFilter) req.services=svcFilter.map(normUuid);
    else if(name) req.name=name;
    else if(namePrefix) req.namePrefix=namePrefix;
    if(opts.optionalServices) req.optionalServices=opts.optionalServices.map(normUuid);
    var d;
    try{
      d=await b.requestDevice(req);
    }catch(e){
      throw notFound((e && e.message) || 'No se eligio ningun dispositivo');
    }
    return new ShimDevice(d.deviceId,d.name);
  },
  /* No hay lista persistente de dispositivos autorizados: la app ya
     contempla este camino y arma el toque manual de sincronizacion. */
  getDevices:async function(){ await ensureInit(); return []; },
  getAvailability:async function(){
    try{ await ensureInit(); var b=await waitBle(); return await b.isEnabled(); }catch(e){ return false; }
  }
};
try{
  Object.defineProperty(navigator,'bluetooth',{value:bluetooth,configurable:true});
}catch(e){
  navigator.bluetooth=bluetooth;
}
/* Aviso visible solo si el plugin no llega a aparecer (diagnóstico en su iPhone). */
waitBle().catch(function(){ nativeBanner('Bluetooth nativo no disponible: el plugin no cargó. Reinicia la app; si sigue, avisa a Adrián.'); });
})();
