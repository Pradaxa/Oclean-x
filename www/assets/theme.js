(function () {
  var KEY = "mg-theme";
  function current() {
    return document.documentElement.dataset.theme === "dark" ? "dark" : "light";
  }
  function sync() {
    var c = document.querySelector(".mg-theme-corner input");
    if (c) c.checked = current() === "dark";
  }
  function apply(v) {
    document.documentElement.dataset.theme = v;
    try { localStorage.setItem(KEY, v); } catch (e) {}
    var m = document.querySelector('meta[name="theme-color"]');
    if (m) m.setAttribute("content", v === "dark" ? "#0c0e0d" : "#73a89a");
    sync();
  }
  /* Interruptor sol-luna con movimiento estilo Liquid Glass (v19).
     Mismo motor de muelles que la referencia: posicion normalizada 0..1 con
     preset drag al seguir el dedo y snap al soltar o tocar, lift (el knob se
     infla al tocar y cae con bamboleo "settle") y jelly (se estira con la
     velocidad y tiembla al parar). Estetica sol/luna original intacta. */
  var TRAVEL = 24; // recorrido del knob en px CSS (pista 60, knob 30, margen 3)
  function rubberband(offset, dimension, constant) {
    var sign = offset < 0 ? -1 : 1;
    var x = Math.abs(offset);
    return sign * (1 - 1 / ((x * constant) / dimension + 1)) * dimension;
  }
  function makeDraggable(label, input, knob, track) {
    var M = window.mgSpring || null;
    var drag = null;
    var suppressClick = false;
    var dropTimer = 0;
    var pos = null;
    var liftS = null;
    var jellyV = 0;
    var jellyFeed = null;
    function checkedPos() {
      return input.checked ? 1 : 0;
    }
    function paint() {
      if (!pos) return;
      var l = liftS ? liftS.value : 0;
      var s = 1 + 0.08 * l;
      var sx = s * (1 + jellyV);
      var sy = s * (1 - jellyV * 0.5);
      knob.style.transform =
        "translateX(" + (pos.value * TRAVEL).toFixed(2) + "px) scale(" +
        sx.toFixed(4) + "," + sy.toFixed(4) + ")";
    }
    if (M) {
      pos = M.make(checkedPos(), function (v, vel) {
        if (jellyFeed) jellyFeed(vel);
        paint();
      });
      liftS = M.make(0, function () { paint(); });
      if (M.makeJelly) {
        jellyFeed = M.makeJelly(function (v) { jellyV = v; paint(); }).feed;
      }
    }
    function liftUp() {
      if (liftS) { liftS.tune(M.presets.lift); liftS.set(1); }
      label.classList.add("tswitch-drag");
    }
    function drop(delay) {
      window.clearTimeout(dropTimer);
      dropTimer = window.setTimeout(function () {
        if (liftS) { liftS.tune(M.presets.settle); liftS.set(0); }
        label.classList.remove("tswitch-drag");
      }, delay);
    }
    function flip(next) {
      input.checked = next;
      apply(next ? "dark" : "light");
      if (pos) {
        knob.style.transition = "none";
        pos.tune(M.presets.snap);
        pos.onrest = function () {
          if (!drag) { knob.style.transform = ""; knob.style.transition = ""; }
        };
        pos.set(next ? 1 : 0);
      }
    }
    function flips(from, raw) { return from ? raw > 0.3 : raw > 0.7; }
    label.addEventListener("pointerdown", function (e) {
      if (e.pointerType === "mouse" && e.button !== 0) return;
      var rect = track.getBoundingClientRect();
      var scale = rect.width > 0 ? rect.width / 60 : 1;
      drag = {
        id: e.pointerId,
        x0: e.clientX,
        scale: scale,
        moved: false,
        pos0: checkedPos(),
        pos: checkedPos(),
        at: e.timeStamp || Date.now()
      };
      try { label.setPointerCapture(e.pointerId); } catch (x) {}
      if (pos) {
        knob.style.transition = "none";
        pos.onrest = null;
        pos.jump(checkedPos());
        paint();
      }
      liftUp();
    });
    label.addEventListener("pointermove", function (e) {
      if (!drag || e.pointerId !== drag.id) return;
      var dx = (e.clientX - drag.x0) / drag.scale;
      if (!drag.moved && Math.abs(dx) < 3) return;
      drag.moved = true;
      var raw = drag.pos0 + dx / TRAVEL;
      var over = raw < 0
        ? rubberband(raw * TRAVEL, TRAVEL, 0.6) / TRAVEL
        : raw > 1
          ? 1 + rubberband((raw - 1) * TRAVEL, TRAVEL, 0.6) / TRAVEL
          : raw;
      drag.pos = over;
      if (pos) {
        pos.tune(M.presets.drag);
        pos.set(over);
      } else {
        knob.style.transform = "translateX(" + Math.max(0, Math.min(TRAVEL, over * TRAVEL)) + "px) scale(1.08)";
      }
    });
    function settle(e) {
      if (!drag || (e && e.pointerId !== drag.id)) return;
      var d = drag;
      drag = null;
      if (!d.moved) {
        // toque simple: el click (tap o teclado) resuelve el cambio
        drop(Math.max(0, 200 - ((e.timeStamp || Date.now()) - d.at)));
        if (!pos) {
          knob.style.transform = "";
          knob.style.transition = "";
          window.clearTimeout(dropTimer);
          label.classList.remove("tswitch-drag");
        }
        return;
      }
      suppressClick = true;
      window.setTimeout(function () { suppressClick = false; }, 350);
      drop(0);
      var next = flips(d.pos0, d.pos);
      if (pos) {
        flip(next);
      } else {
        input.checked = next;
        apply(next ? "dark" : "light");
        knob.style.transform = "translateX(" + (next ? TRAVEL : 0) + "px) scale(1)";
        window.setTimeout(function () { knob.style.transform = ""; knob.style.transition = ""; }, 560);
      }
    }
    label.addEventListener("pointerup", settle);
    label.addEventListener("pointercancel", function (e) {
      if (!drag || e.pointerId !== drag.id) return;
      drag = null;
      drop(0);
      if (pos) {
        pos.tune(M.presets.snap);
        pos.onrest = function () { knob.style.transform = ""; knob.style.transition = ""; };
        pos.set(checkedPos());
      } else {
        knob.style.transform = "";
        knob.style.transition = "";
      }
    });
    label.addEventListener("click", function (e) {
      if (suppressClick) {
        suppressClick = false;
        e.preventDefault();
        e.stopPropagation();
        return;
      }
      if (drag) {
        // pointerup/cancel perdido: resolver el gesto aqui para no dejar el knob colgado
        var d = drag;
        drag = null;
        if (d.moved) {
          e.preventDefault();
          e.stopPropagation();
          drop(0);
          var n = flips(d.pos0, d.pos);
          if (pos) flip(n);
          return;
        }
        drop(0);
      }
      if (!pos) return; // sin muelles: toggle nativo y change de respaldo
      e.preventDefault();
      e.stopPropagation();
      // tap o teclado: levanta un instante y cruza con muelle
      if (liftS && liftS.value < 0.5) liftUp();
      drop(120);
      flip(!input.checked);
    }, true);
    // Respaldo sin muelles: el change nativo mantiene el tema al dia.
    input.addEventListener("change", function () {
      apply(input.checked ? "dark" : "light");
    });
  }
  function build() {
    var label = document.createElement("label");
    label.className = "tswitch tswitch-mini";
    var input = document.createElement("input");
    input.type = "checkbox";
    input.setAttribute("aria-label", "Modo oscuro");
    input.checked = current() === "dark";
    var track = document.createElement("span");
    track.className = "tswitch-track";
    track.setAttribute("aria-hidden", "true");
    var knob = document.createElement("span");
    knob.className = "tswitch-knob";
    track.appendChild(knob);
    label.appendChild(input);
    label.appendChild(track);
    makeDraggable(label, input, knob, track);
    var corner = document.createElement("div");
    corner.className = "mg-theme-corner";
    corner.appendChild(label);
    return corner;
  }
  function scan() {
    var tabs = document.querySelectorAll(".mg-tab");
    for (var i = 0; i < tabs.length; i++) {
      var tab = tabs[i];
      if (tab.querySelector(".mg-settings") && !tab.querySelector(".mg-theme-corner")) {
        tab.classList.add("mg-has-theme-corner");
        tab.insertBefore(build(), tab.firstChild);
      }
    }
    sync();
  }
  var obs = new MutationObserver(function () { scan(); });
  function start() {
    var root = document.getElementById("root") || document.documentElement;
    obs.observe(root, { childList: true, subtree: true });
    scan();
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start);
  } else {
    start();
  }
  try {
    window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", function (e) {
      var s = null;
      try { s = localStorage.getItem(KEY); } catch (x) {}
      if (s !== "dark" && s !== "light") {
        document.documentElement.dataset.theme = e.matches ? "dark" : "light";
        var m = document.querySelector('meta[name="theme-color"]');
        if (m) m.setAttribute("content", e.matches ? "#0c0e0d" : "#73a89a");
        sync();
      }
    });
  } catch (e) {}
})();
