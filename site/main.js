/* Two things: copy buttons on the command blocks, and the film lightbox. */

/* Copy buttons on the command blocks. */
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

/* The film lightbox. A native <dialog>, so Escape and focus containment are the
   platform's job rather than ours. Playback starts on open and is paused and
   rewound on close — a closed dialog that goes on playing to an empty room is
   both a wasted download and a surprise if it is reopened mid-film. */
(function () {
  "use strict";

  var dialog = document.getElementById("film");
  var trigger = document.querySelector("[data-film]");
  var video = dialog && dialog.querySelector("video");
  /* All three up front, so nothing below has to re-check. Guarding `video` only
     at some use sites is how the play-invariant listener below ends up being the
     one that throws, which would leave the click handler registered and the
     invariant silently uninstalled — the worst of both. */
  if (!dialog || !trigger || !video || typeof dialog.showModal !== "function") { return; }

  trigger.addEventListener("click", function () {
    dialog.showModal();
    /* Assign the poster on first open. A closed dialog is display:none, which
       defers the video but not a `poster` attribute, so leaving it in the markup
       billed every visitor 130KB for a frame most never see. */
    if (video.dataset.poster) {
      video.poster = video.dataset.poster;
      delete video.dataset.poster;
    }
    var played = video.play();
    /* Autoplay policy can refuse even a user-initiated play on some
       configurations, and pausing mid-play rejects with AbortError. The controls
       are there, so a refusal is recoverable and an unhandled rejection in the
       console is not worth it. */
    if (played && played.catch) { played.catch(function () {}); }
  });

  dialog.addEventListener("close", stop);

  /* The invariant, rather than a race to win: the film never plays to a shut
     dialog. A `pause()` issued from the close handler does not stick if it lands
     while the `play()` promise is still unsettled — playback starts anyway once
     it resolves, and a closed <dialog> is display:none, so the film goes on
     playing where nobody can see it. Asserting it here catches that ordering and
     every other one, because whatever route playback starts by, it fires `play`. */
  video.addEventListener("play", function () {
    if (!dialog.open) { stop(); }
  });

  function stop() {
    video.pause();
    video.currentTime = 0;
  }

  /* Clicking the backdrop closes it: the dialog element itself is the click
     target when the press lands outside its content box. */
  dialog.addEventListener("click", function (event) {
    if (event.target === dialog) { dialog.close(); }
  });
})();
