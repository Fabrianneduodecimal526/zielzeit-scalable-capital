/* Copy buttons on the command blocks. That is all this page needs. */
(function () {
  "use strict";

  Array.prototype.forEach.call(document.querySelectorAll(".copy"), function (btn) {
    btn.addEventListener("click", function () {
      var text = btn.getAttribute("data-copy");

      var done = function () {
        var was = btn.textContent;
        btn.textContent = "Copied";
        btn.setAttribute("data-done", "");
        setTimeout(function () {
          btn.textContent = was;
          btn.removeAttribute("data-done");
        }, 1600);
      };

      var fallback = function () {
        var field = document.createElement("textarea");
        field.value = text;
        field.setAttribute("readonly", "");
        field.style.position = "fixed";
        field.style.opacity = "0";
        document.body.appendChild(field);
        field.select();
        try { document.execCommand("copy"); done(); } catch (e) { btn.textContent = "Press ⌘C"; }
        document.body.removeChild(field);
      };

      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, fallback);
      } else {
        fallback();
      }
    });
  });
})();
