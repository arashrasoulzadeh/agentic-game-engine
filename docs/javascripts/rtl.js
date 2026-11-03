// Pages under /fa/ are Persian: render their content right-to-left.
(function () {
  function apply() {
    var fa = /\/fa(\/|$)/.test(location.pathname);
    document.body.classList.toggle("zv-rtl", fa);
  }
  if (window.document$) window.document$.subscribe(apply);
  else document.addEventListener("DOMContentLoaded", apply);
})();
