/* Puente Web Bluetooth -> Capacitor BLE (solo app nativa).
   En la web normal este archivo no hace nada: window.Capacitor no existe.
   En la app nativa implementa navigator.bluetooth con la misma forma que la
   Web Bluetooth API para que app.js funcione sin cambios. */
(function(){
'use strict';
if(!(window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform())) return;
var Plugins = window.Capacitor.Plugins || {};
var BleClient = Plugins.BleClient;
if(!BleClient) return;

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
  var self=this;
  await BleClient.startNotifications(this._deviceId,this._svc,this.uuid,function(value){
    self._emit('characteristicvaluechanged',toDataView(value));
  });
};
ShimCharacteristic.prototype.stopNotifications=async function(){
  await BleClient.stopNotifications(this._deviceId,this._svc,this.uuid);
};
ShimCharacteristic.prototype.readValue=async function(){
  return toDataView(await BleClient.read(this._deviceId,this._svc,this.uuid));
};
ShimCharacteristic.prototype.writeValue=async function(v){
  await BleClient.write(this._deviceId,this._svc,this.uuid,toDataView(v));
};
ShimCharacteristic.prototype.writeValueWithResponse=ShimCharacteristic.prototype.writeValue;
ShimCharacteristic.prototype.writeValueWithoutResponse=async function(v){
  await BleClient.writeWithoutResponse(this._deviceId,this._svc,this.uuid,toDataView(v));
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
  var self=this;
  await BleClient.connect(this._dev.id,function(){ self.connected=false; });
  var services=await BleClient.getServices(this._dev.id);
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
  try{ await BleClient.disconnect(this._dev.id); }catch(e){}
  this.connected=false;
};

function ShimDevice(id,name){
  this.id=id;
  this.name=name||'';
  this.gatt=new ShimServer(this);
}

/* ---------- navigator.bluetooth ---------- */
var initDone=null;
function ensureInit(){
  if(!initDone) initDone=BleClient.initialize();
  return initDone;
}
var bluetooth={
  requestDevice:async function(opts){
    await ensureInit();
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
      d=await BleClient.requestDevice(req);
    }catch(e){
      throw notFound((e && e.message) || 'No se eligio ningun dispositivo');
    }
    return new ShimDevice(d.deviceId,d.name);
  },
  /* No hay lista persistente de dispositivos autorizados: la app ya
     contempla este camino y arma el toque manual de sincronizacion. */
  getDevices:async function(){ await ensureInit(); return []; },
  getAvailability:async function(){
    try{ await ensureInit(); return await BleClient.isEnabled(); }catch(e){ return false; }
  }
};
try{
  Object.defineProperty(navigator,'bluetooth',{value:bluetooth,configurable:true});
}catch(e){
  navigator.bluetooth=bluetooth;
}
})();
