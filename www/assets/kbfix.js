(function () {
  var r = document.documentElement;
  function update() {
    var v = window.visualViewport;
    if (!v) return;
    var kb = Math.round(window.innerHeight - v.height - v.offsetTop);
    if (kb < 60) kb = 0;
    r.style.setProperty('--mg-kb', kb + 'px');
    r.style.setProperty('--mg-vvh', Math.round(v.height) + 'px');
  }
  window.__mgKb = update;
  if (window.visualViewport) {
    window.visualViewport.addEventListener('resize', update);
    window.visualViewport.addEventListener('scroll', update);
  }
  window.addEventListener('resize', update);
  window.addEventListener('orientationchange', function () { setTimeout(update, 300); });
  document.addEventListener('focusin', function () { setTimeout(update, 50); setTimeout(update, 350); });
  document.addEventListener('focusout', function () { setTimeout(update, 50); setTimeout(update, 350); });
  update();
})();
