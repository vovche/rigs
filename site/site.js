// Rigs landing: install tabs, copy buttons, remembered language choice.
// Without JavaScript every install panel is simply shown one after another.
(function () {
  document.documentElement.classList.add("js");

  // Manual language switch wins over browser preferences from now on (see the head script).
  document.querySelectorAll("a[data-lang]").forEach(function (link) {
    link.addEventListener("click", function () {
      try { localStorage.setItem("rigs-lang", link.dataset.lang); } catch (e) { /* private mode */ }
    });
  });

  var tabs = Array.prototype.slice.call(document.querySelectorAll('[role="tab"]'));
  function select(tab, focus) {
    tabs.forEach(function (t) {
      var on = t === tab;
      t.setAttribute("aria-selected", on ? "true" : "false");
      t.tabIndex = on ? 0 : -1;
      document.getElementById(t.getAttribute("aria-controls")).hidden = !on;
    });
    if (focus) tab.focus();
    try { localStorage.setItem("rigs-tab", tab.id); } catch (e) { /* ignore */ }
  }
  tabs.forEach(function (tab, i) {
    tab.addEventListener("click", function () { select(tab, false); });
    tab.addEventListener("keydown", function (e) {
      var next = e.key === "ArrowRight" ? i + 1 : e.key === "ArrowLeft" ? i - 1 : null;
      if (next === null) return;
      e.preventDefault();
      select(tabs[(next + tabs.length) % tabs.length], true);
    });
  });
  var saved = null;
  try { saved = document.getElementById(localStorage.getItem("rigs-tab") || ""); } catch (e) { /* ignore */ }
  // A guess from the browser: Fedora's Firefox says so in its user agent.
  if (!saved && /Fedora/i.test(navigator.userAgent)) saved = document.getElementById("tab-rpm");
  if (tabs.length) select(saved && tabs.indexOf(saved) >= 0 ? saved : tabs[0], false);

  document.querySelectorAll(".copy").forEach(function (button) {
    var label = button.textContent;
    button.addEventListener("click", function () {
      var text = button.parentElement.querySelector("code").textContent;
      navigator.clipboard.writeText(text).then(function () {
        button.textContent = button.dataset.copied;
        setTimeout(function () { button.textContent = label; }, 1600);
      });
    });
  });
})();
