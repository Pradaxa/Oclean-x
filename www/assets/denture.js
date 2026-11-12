/* Mi Cepillo — dentadura 3D sobre el modelo GLB de Adrián.
   Coloreado por zona Oclean (8: sup/inf × izq/der × ext/int) por vértice.
   Sin auto-rotación: solo gira al arrastrar; la página no hace scroll al tocarlo. */
import * as THREE from './vendor/three.module.min.js';
import { GLTFLoader } from './vendor/GLTFLoader.js';

const COLORS = {
  good: new THREE.Color(0xeae5da), // bien cepillada (marfil grisáceo mate, estilo app oficial)
  mid:  new THREE.Color(0xf0a6ba), // regular
  bad:  new THREE.Color(0xe0455a), // mal cepillada
  none: new THREE.Color(0xd8d2c6), // sin datos
};
const BASE_TILT = 0.14; // inclinación inicial: vista frontal de la captura de Adrián (12:52)

// Textura de encía copiada del visor de Gemini (gradiente rosa + ruido + venas)
function createGumNoiseTexture() {
  const cv = document.createElement('canvas');
  cv.width = 512; cv.height = 512;
  const ctx = cv.getContext('2d');
  const grad = ctx.createLinearGradient(0, 0, 0, 512);
  grad.addColorStop(0, '#de9a9c');
  grad.addColorStop(0.5, '#d3898d');
  grad.addColorStop(1, '#c4777d');
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, 512, 512);
  const imgData = ctx.getImageData(0, 0, 512, 512);
  const data = imgData.data;
  for (let i = 0; i < data.length; i += 4) {
    const noise = (Math.random() - 0.5) * 18;
    data[i] = Math.min(255, Math.max(0, data[i] + noise));
    data[i + 1] = Math.min(255, Math.max(0, data[i + 1] + noise * 0.5));
    data[i + 2] = Math.min(255, Math.max(0, data[i + 2] + noise * 0.6));
  }
  ctx.putImageData(imgData, 0, 0);
  ctx.strokeStyle = 'rgba(150, 60, 70, 0.15)';
  ctx.lineWidth = 1.5;
  for (let i = 0; i < 15; i++) {
    ctx.beginPath();
    let x = Math.random() * 512, y = Math.random() * 512;
    ctx.moveTo(x, y);
    for (let j = 0; j < 5; j++) {
      x += (Math.random() - 0.5) * 60;
      y += (Math.random() - 0.5) * 60;
      ctx.lineTo(x, y);
    }
    ctx.stroke();
  }
  const texture = new THREE.CanvasTexture(cv);
  texture.wrapS = THREE.RepeatWrapping;
  texture.wrapT = THREE.RepeatWrapping;
  texture.repeat.set(2, 2);
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}
let gumMaterial = null;
function getGumMaterial() {
  if (!gumMaterial) {
    const tex = createGumNoiseTexture();
    gumMaterial = new THREE.MeshStandardMaterial({
      color: 0xf2e4e0, // tinte que apaga el rosa hacia el tono empolvado de la referencia
      map: tex, bumpMap: tex, bumpScale: 0.03,
      roughness: 0.4, metalness: 0.05,
      side: THREE.DoubleSide, // las conchas de encía del nuevo modelo son abiertas
      emissive: 0x4a2024, emissiveIntensity: 0.32, // el interior de la boca no se apaga
    });
  }
  return gumMaterial;
}
// Esmalte con el brillo del visor de Gemini (r160: sheen numérico + sheenColor)
let toothMaterial = null;
function getToothMaterial() {
  if (!toothMaterial) {
    toothMaterial = new THREE.MeshPhysicalMaterial({
      color: 0xffffff, vertexColors: true, // el coloreado por zonas vive en los vértices
      roughness: 0.18, metalness: 0.02,
      clearcoat: 0.8, clearcoatRoughness: 0.1,
      reflectivity: 0.9, sheen: 0.2, sheenColor: new THREE.Color(0xffffff),
      transmission: 0.15, thickness: 0.8,
    });
  }
  return toothMaterial;
}
// three.js sanea los nombres del GLB (espacios->_ y sin acentos): 'Superior molar 1' -> 'Superior_molar_1'
const TOOTH_RE = /(Superior|Inferior)[^\d]*?(\d+)$/;

let templatePromise = null;
let meta = null; // { groups: Map<nodeName,{arch,N}>, centerY }

function analyze(scene) {
  const groups = new Map();
  const box = new THREE.Box3();
  let yc = 0, cnt = 0;
  scene.updateMatrixWorld(true);
  scene.traverse((o) => {
    if (!o.isMesh) return;
    // el GLB no trae normales: las calculamos suaves para el shading
    if (!o.geometry.attributes.normal) o.geometry.computeVertexNormals();
    if (o.material && o.material.flatShading) o.material.flatShading = false;
    const name = o.name || '';
    if (/^Enc|^Relieve/.test(name)) {
      // el GLB no trae UVs: proyección plana sobre el arco para la textura
      if (!o.geometry.attributes.uv) {
        o.geometry.computeBoundingBox();
        const gb = o.geometry.boundingBox;
        const sx = Math.max(1e-6, gb.max.x - gb.min.x);
        const sy = Math.max(1e-6, gb.max.y - gb.min.y);
        const p = o.geometry.attributes.position;
        const uv = new Float32Array(p.count * 2);
        for (let i = 0; i < p.count; i++) {
          uv[i * 2] = (p.getX(i) - gb.min.x) / sx;
          uv[i * 2 + 1] = (p.getY(i) - gb.min.y) / sy;
        }
        o.geometry.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
      }
      o.material = getGumMaterial();
      box.expandByObject(o);
    }
  });
  yc = (box.min.y + box.max.y) / 2;
  scene.traverse((o) => {
    if (!o.isMesh) return;
    const m = TOOTH_RE.exec(o.name || '');
    if (!m) return;
    groups.set(o.name, { arch: m[1], N: parseInt(m[2], 10), yc });
  });
  return { groups, yc };
}

function loadTemplate() {
  if (!templatePromise) {
    templatePromise = new Promise((resolve, reject) => {
      new GLTFLoader().load('./assets/dentadura.glb?v=11', (g) => {
        meta = analyze(g.scene);
        resolve(g.scene);
      }, undefined, reject);
    });
  }
  return templatePromise;
}

function colorize(root, classes) {
  const tmp = new THREE.Vector3();
  root.traverse((o) => {
    if (!o.isMesh) return;
    const info = meta.groups.get(o.name);
    if (!info) return; // encías conservan su material
    const { arch, N, yc } = info;
    // dientes 1-7 = izquierda de la persona (SI/II), 8-14 = derecha (SD/ID)
    const left = N <= 7;
    const ziExt = arch === 'Superior' ? (left ? 0 : 4) : (left ? 2 : 6);
    const ziInt = ziExt + 1;
    const cExt = COLORS[classes[ziExt]] || COLORS.none;
    const cInt = COLORS[classes[ziInt]] || COLORS.none;
    o.geometry = o.geometry.clone();
    const geo = o.geometry;
    const pos = geo.attributes.position;
    // centro y dirección radial del diente (en coords locales del modelo, Z-up)
    const c = new THREE.Vector3();
    for (let i = 0; i < pos.count; i++) c.add(tmp.fromBufferAttribute(pos, i));
    c.multiplyScalar(1 / pos.count);
    const r = new THREE.Vector2(c.x, c.y - yc).normalize();
    // semiancho radial para suavizar la frontera ext/int
    let maxd = 0.0001;
    for (let i = 0; i < pos.count; i++) {
      tmp.fromBufferAttribute(pos, i);
      const d = Math.abs((tmp.x - c.x) * r.x + (tmp.y - c.y) * r.y);
      if (d > maxd) maxd = d;
    }
    const w = maxd * 0.45;
    const colors = new Float32Array(pos.count * 3);
    const col = new THREE.Color();
    for (let i = 0; i < pos.count; i++) {
      tmp.fromBufferAttribute(pos, i);
      const d = (tmp.x - c.x) * r.x + (tmp.y - c.y) * r.y;
      let t = Math.min(1, Math.max(0, d / w * 0.5 + 0.5)); // 0=int 1=ext
      col.copy(cInt).lerp(cExt, t);
      colors[i * 3] = col.r; colors[i * 3 + 1] = col.g; colors[i * 3 + 2] = col.b;
    }
    geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
    o.material = getToothMaterial();
  });
}

const liveByCanvas = new WeakMap();
let liveAll = [];

export async function mountLive(canvas, classes) {
  if (liveByCanvas.has(canvas)) return liveByCanvas.get(canvas);
  let renderer;
  try {
    renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
  } catch (e) { canvas.style.display = 'none'; return null; }
  const template = await loadTemplate();
  if (liveByCanvas.has(canvas)) return liveByCanvas.get(canvas);
  const w = canvas.clientWidth || 300, h = canvas.clientHeight || 280;
  renderer.setSize(w, h, false);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.outputColorSpace = THREE.SRGBColorSpace;

  const scene = new THREE.Scene();
  const cam = new THREE.PerspectiveCamera(38, w / h, 0.1, 50);
  scene.add(new THREE.HemisphereLight(0xfff4f0, 0x402025, 1.35));
  const key = new THREE.DirectionalLight(0xffffff, 1.25);
  key.position.set(2.5, 3.5, 4);
  scene.add(key);
  const fill = new THREE.DirectionalLight(0xffd9e0, 0.45);
  fill.position.set(-3, -2, 3);
  scene.add(fill);

  const inst = template.clone(true);
  colorize(inst, classes);
  const wrap = new THREE.Group();
  inst.rotation.x = -Math.PI / 2; // el modelo es Z-up
  wrap.add(inst);
  wrap.rotation.x = BASE_TILT; // medir YA inclinado: la profundidad también ocupa alto en pantalla
  const bb = new THREE.Box3().setFromObject(wrap);
  const c = bb.getCenter(new THREE.Vector3());
  inst.position.sub(c);
  scene.add(wrap);
  const size = bb.getSize(new THREE.Vector3());
  // en la vista Hoy DE LA WEB el dock flota sobre el lienzo: elevar el modelo lo justo para librarlo.
  // En la app nativa (y en la hoja) no hay dock: modelo centrado y a tamaño completo.
  const inSheet = !!canvas.closest('.mg-sheet');
  const nativeShell = !!(document.documentElement && document.documentElement.dataset.shell === 'native');
  const liftFrac = (inSheet || nativeShell) ? 0 : 0.20;
  inst.position.y += size.y * liftFrac;
  // lienzo de Hoy alto (400px): cabe la boca entera y la zona de arrastre es cómoda
  const fit = Math.max(size.x / cam.aspect, size.y);
  const dist = fit * 0.5 / Math.tan(THREE.MathUtils.degToRad(19)) * ((inSheet || nativeShell) ? 1.16 : 1.30);
  cam.position.set(0, -0.6, dist); // cámara algo baja: la arcada inferior se ve más cerca, como en la referencia de Adrián
  cam.lookAt(0, 0, 0);

  let rotY = 0, rotX = 0, tRotY = 0, tRotX = 0;
  let zoom = 1, tZoom = 1; // zoom por pellizco (solo app nativa; en la web queda en 1)
  let dragging = false, px = 0, py = 0, raf = 0, dead = false;
  let nativeDrag = false; // obsoleto: la app nativa tambien usa pointer events (ver abajo)
  /* Gestos EN PROCESO: conducirlos desde SwiftUI con evaluateJavaScript por
     frame hacia que el render fuera a golpes en el iPhone real (las llamadas
     llegan en ráfagas). Aqui los pointer events alimentan directamente el
     bucle rAF, igual que en la web. La app nativa ademas tiene pellizco y
     doble toque, y reporta su estado a Swift por onRotState. */
  const ptrs = new Map(); // pointerId -> [x, y]
  let pinchD = 0, movedPx = 0, lastTap = 0;
  let rotReporter = null, lastRotReport = 0;
  /* Bloqueo del scroll de la pantalla mientras se gira el 3D (app nativa):
     la vista avisa a Swift por este hook para que el ScrollView no compita
     con el arrastre. En la web nadie lo registra y no se llama. */
  let scrollLocker = null;
  function lockScroll(on) { if (scrollLocker) try { scrollLocker(on); } catch (e) {} }
  function frame() {
    if (dead) return;
    rotY += (tRotY - rotY) * 0.16;
    rotX += (tRotX - rotX) * 0.16;
    zoom += (tZoom - zoom) * 0.2;
    wrap.rotation.y = rotY;
    wrap.rotation.x = BASE_TILT + rotX;
    cam.position.set(0, -0.6, dist / zoom);
    cam.lookAt(0, 0, 0);
    renderer.render(scene, cam);
    if (rotReporter) {
      const now = performance.now();
      if (now - lastRotReport > 120) { lastRotReport = now; try { rotReporter(rotY, rotX, zoom); } catch (e) {} }
    }
    if (dragging || Math.abs(tRotY - rotY) > 0.0004 || Math.abs(tRotX - rotX) > 0.0004 || Math.abs(tZoom - zoom) > 0.001) raf = requestAnimationFrame(frame);
    else raf = 0;
  }
  function rot(dx, dy) { // entrada externa opcional (misma escala que el arrastre)
    tRotY += dx * 0.011;
    tRotX = Math.max(-0.85, Math.min(0.85, tRotX + dy * 0.007));
    if (!raf) raf = requestAnimationFrame(frame);
  }
  function zoomBy(f) { // entrada externa opcional
    tZoom = Math.max(0.5, Math.min(3, tZoom * f));
    if (!raf) raf = requestAnimationFrame(frame);
  }
  function down(e) {
    if (nativeDrag) return;
    if (ptrs.size === 0) lockScroll(true);
    ptrs.set(e.pointerId, [e.clientX, e.clientY]);
    if (nativeShell && ptrs.size === 2) {
      const p = [...ptrs.values()];
      pinchD = Math.hypot(p[0][0] - p[1][0], p[0][1] - p[1][1]);
      dragging = false;
    } else {
      dragging = true; px = e.clientX; py = e.clientY; movedPx = 0;
    }
    if (canvas.setPointerCapture) try { canvas.setPointerCapture(e.pointerId); } catch (err) {}
    if (!raf) raf = requestAnimationFrame(frame);
  }
  function move(e) {
    if (nativeDrag || !ptrs.has(e.pointerId)) return;
    ptrs.set(e.pointerId, [e.clientX, e.clientY]);
    if (e.cancelable) e.preventDefault();
    if (nativeShell && ptrs.size === 2) { // pellizco: zoom por distancia entre dedos
      const p = [...ptrs.values()];
      const d = Math.hypot(p[0][0] - p[1][0], p[0][1] - p[1][1]);
      if (pinchD > 0 && d > 0) tZoom = Math.max(0.5, Math.min(3, tZoom * d / pinchD));
      pinchD = d;
      return;
    }
    if (!dragging) return;
    movedPx += Math.abs(e.clientX - px) + Math.abs(e.clientY - py);
    tRotY += (e.clientX - px) * 0.011;
    tRotX = Math.max(-0.85, Math.min(0.85, tRotX + (e.clientY - py) * 0.007));
    px = e.clientX; py = e.clientY;
  }
  function up(e) {
    ptrs.delete(e.pointerId);
    if (ptrs.size === 0) lockScroll(false);
    if (ptrs.size < 2) pinchD = 0;
    if (ptrs.size === 1) { const p = [...ptrs.values()][0]; px = p[0]; py = p[1]; movedPx = 0; dragging = true; }
    if (ptrs.size === 0) {
      const wasTap = movedPx < 12;
      dragging = false;
      // doble toque -> posicion inicial (la web usa dblclick, que en iOS no es fiable)
      if (nativeShell && wasTap) {
        const n = performance.now();
        if (n - lastTap < 320) { reset(); lastTap = 0; } else lastTap = n;
      }
    }
  }
  function reset() { tRotY = 0; tRotX = 0; tZoom = 1; if (!raf) raf = requestAnimationFrame(frame); } // posición 0
  canvas.addEventListener('dblclick', reset);
  canvas.addEventListener('pointerdown', down);
  canvas.addEventListener('pointermove', move);
  canvas.addEventListener('pointerup', up);
  canvas.addEventListener('pointercancel', up);
  /* Rescate de pellizco en WKWebView: a veces WebKit enruta el gesto de dos
     dedos a sus eventos gesture* en lugar de pointer events (p. ej. el
     pellizco sintetizado por las pruebas de UI). Solo cuenta si el pellizco
     por punteros no está activo, para no aplicar el zoom dos veces. */
  let gScale = 1;
  canvas.addEventListener('gesturestart', function (e) { e.preventDefault(); gScale = e.scale || 1; });
  canvas.addEventListener('gesturechange', function (e) {
    e.preventDefault();
    if (!nativeShell || ptrs.size >= 2) { gScale = e.scale || 1; return; }
    const s = e.scale || 1;
    if (gScale > 0) tZoom = Math.max(0.5, Math.min(3, tZoom * s / gScale));
    gScale = s;
    if (!raf) raf = requestAnimationFrame(frame);
  });
  canvas.addEventListener('gestureend', function (e) { e.preventDefault(); gScale = 1; });
  renderer.render(scene, cam); // estático hasta que se toca
  const api = {
    dispose() { dead = true; cancelAnimationFrame(raf); lockScroll(false); liveByCanvas.delete(canvas); renderer.dispose(); },
    rot, zoomBy, resetRot: reset,
    disablePointerDrag() { nativeDrag = true; },
    setRotReporter(fn) { rotReporter = fn; },
    setScrollLocker(fn) { scrollLocker = fn; },
    // Recolorear EN CALIENTE sin desmontar: mismo render, mismas luces.
    // En la app nativa remontar (dispose + nuevo renderer sobre el mismo canvas)
    // es frágil en WKWebView; recolorear la instancia viva no falla nunca.
    recolor(newClasses) { colorize(inst, newClasses); renderer.render(scene, cam); }
  };
  liveByCanvas.set(canvas, api);
  liveAll.push(api);
  return api;
}

export function disposeAll() {
  while (liveAll.length) { try { liveAll.pop().dispose(); } catch (e) {} }
}
