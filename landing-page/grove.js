/* grove landing page — interactions & ambient canvas */
(function () {
  "use strict";
  var reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ---------- Theme toggle ---------- */
  var toggle = document.getElementById("theme-toggle");
  function currentTheme() {
    var attr = document.documentElement.getAttribute("data-theme");
    if (attr) return attr;
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }
  if (toggle) {
    toggle.addEventListener("click", function () {
      var next = currentTheme() === "dark" ? "light" : "dark";
      document.documentElement.setAttribute("data-theme", next);
      try { localStorage.setItem("grove-theme", next); } catch (e) {}
    });
  }

  /* ---------- Sticky header shadow ---------- */
  var masthead = document.getElementById("masthead");
  function onScroll() {
    if (masthead) masthead.classList.toggle("scrolled", window.scrollY > 8);
  }
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  /* ---------- Copy buttons ---------- */
  function wireCopy(btn) {
    if (!btn) return;
    var targetId = btn.getAttribute("data-copy-target");
    var label = btn.querySelector(".copy-label");
    btn.addEventListener("click", function () {
      var el = document.getElementById(targetId);
      if (!el) return;
      var text = el.innerText.replace(/ /g, " ");
      var done = function () {
        btn.classList.add("copied");
        if (label) label.textContent = "Copied";
        setTimeout(function () {
          btn.classList.remove("copied");
          if (label) label.textContent = "Copy";
        }, 1900);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, function () { legacyCopy(text, done); });
      } else {
        legacyCopy(text, done);
      }
    });
  }
  function legacyCopy(text, done) {
    var ta = document.createElement("textarea");
    ta.value = text; ta.style.position = "fixed"; ta.style.opacity = "0";
    document.body.appendChild(ta); ta.select();
    try { document.execCommand("copy"); done(); } catch (e) {}
    document.body.removeChild(ta);
  }
  wireCopy(document.getElementById("copy-bootstrap"));
  wireCopy(document.getElementById("copy-full"));

  /* ---------- Load full guided-setup prompt from shared file ---------- */
  (function loadPrompt() {
    var pre = document.getElementById("full-prompt-text");
    if (!pre) return;
    fetch("install-prompt.txt", { cache: "no-cache" })
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.text(); })
      .then(function (t) { pre.textContent = t.replace(/\s+$/, ""); })
      .catch(function () {
        pre.textContent =
          "Couldn't load the prompt here — read it in the grove README:\n" +
          "https://github.com/shivgodhia/grove#installation";
        var src = document.getElementById("fp-source");
        if (src) src.textContent = "unavailable offline — see the README";
      });
  })();

  /* ---------- Reveal on scroll ---------- */
  var revealEls = document.querySelectorAll(".reveal");
  if ("IntersectionObserver" in window && !reduceMotion) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e, i) {
        if (e.isIntersecting) {
          var el = e.target;
          setTimeout(function () { el.classList.add("in"); }, (i % 3) * 90);
          io.unobserve(el);
        }
      });
    }, { threshold: 0.14, rootMargin: "0px 0px -8% 0px" });
    revealEls.forEach(function (el) { io.observe(el); });
  } else {
    revealEls.forEach(function (el) { el.classList.add("in"); });
  }

  /* ---------- Hero terminal: stagger the rows in ---------- */
  (function animateTerminal() {
    var rows = document.querySelectorAll("#term-body .row");
    if (!rows.length) return;
    if (reduceMotion) { rows.forEach(function (r) { r.classList.add("show"); }); return; }
    rows.forEach(function (r) { r.style.opacity = "0"; });
    var i = 0;
    (function next() {
      if (i >= rows.length) return;
      rows[i].style.opacity = "";
      rows[i].classList.add("show");
      i++;
      setTimeout(next, 260);
    })();
  })();

  /* ---------- Ambient canvas: drifting leaf-light + branching trees ---------- */
  (function grove() {
    var canvas = document.getElementById("grove-canvas");
    if (!canvas) return;
    var ctx = canvas.getContext("2d");
    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    var W = 0, H = 0;
    var motes = [];
    var trees = [];

    function themeColors() {
      var dark = currentTheme() === "dark";
      return dark
        ? { mote: [199, 217, 140], tree: "rgba(199,217,140,0.06)", moteA: 0.5 }
        : { mote: [91, 140, 81], tree: "rgba(64,105,58,0.05)", moteA: 0.42 };
    }

    function resize() {
      W = canvas.offsetWidth; H = canvas.offsetHeight;
      canvas.width = W * dpr; canvas.height = H * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      buildTrees();
    }

    // Faint branching "worktrees" silhouettes rooted along the bottom.
    function buildTrees() {
      trees = [];
      var count = W < 640 ? 2 : W < 1000 ? 3 : 4;
      for (var i = 0; i < count; i++) {
        trees.push({
          x: (W / (count + 1)) * (i + 1) + (i % 2 ? 40 : -30),
          scale: 0.7 + (i % 3) * 0.22,
          sway: 0
        });
      }
    }

    function drawBranch(x, y, len, ang, depth, sway) {
      if (depth === 0 || len < 6) return;
      var nx = x + Math.cos(ang) * len;
      var ny = y + Math.sin(ang) * len;
      ctx.lineWidth = depth * 0.6;
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(nx, ny);
      ctx.stroke();
      var spread = 0.5 + sway;
      drawBranch(nx, ny, len * 0.72, ang - spread, depth - 1, sway);
      drawBranch(nx, ny, len * 0.72, ang + spread, depth - 1, sway);
    }

    function spawnMote() {
      return {
        x: Math.random() * W,
        y: Math.random() * H,
        r: 0.6 + Math.random() * 2.2,
        vx: -0.12 - Math.random() * 0.28,
        vy: 0.08 + Math.random() * 0.22,
        drift: Math.random() * Math.PI * 2,
        driftSpeed: 0.004 + Math.random() * 0.01,
        a: 0.15 + Math.random() * 0.5
      };
    }

    function initMotes() {
      var n = W < 640 ? 26 : W < 1100 ? 44 : 64;
      motes = [];
      for (var i = 0; i < n; i++) motes.push(spawnMote());
    }

    var t = 0;
    function frame() {
      var c = themeColors();
      ctx.clearRect(0, 0, W, H);

      // Trees (very faint, swaying)
      ctx.strokeStyle = c.tree;
      ctx.lineCap = "round";
      for (var i = 0; i < trees.length; i++) {
        var tr = trees[i];
        var sway = Math.sin(t * 0.0006 + i) * 0.06;
        drawBranch(tr.x, H, 46 * tr.scale, -Math.PI / 2, 7, 0.42 + sway);
      }

      // Leaf-light motes
      for (var j = 0; j < motes.length; j++) {
        var m = motes[j];
        m.drift += m.driftSpeed;
        m.x += m.vx + Math.cos(m.drift) * 0.25;
        m.y += m.vy;
        if (m.x < -10 || m.y > H + 10) {
          motes[j] = spawnMote();
          motes[j].x = W + 10;
          motes[j].y = Math.random() * H * 0.4;
          continue;
        }
        var pulse = 0.6 + 0.4 * Math.sin(t * 0.02 + j);
        ctx.beginPath();
        ctx.arc(m.x, m.y, m.r, 0, Math.PI * 2);
        ctx.fillStyle = "rgba(" + c.mote[0] + "," + c.mote[1] + "," + c.mote[2] + "," + (m.a * c.moteA * pulse).toFixed(3) + ")";
        ctx.fill();
      }

      t++;
      raf = requestAnimationFrame(frame);
    }

    var raf = null;
    function start() {
      resize();
      initMotes();
      if (reduceMotion) { drawStatic(); return; }
      if (!raf) raf = requestAnimationFrame(frame);
    }
    function drawStatic() {
      // One calm frame for reduced-motion users.
      var c = themeColors();
      ctx.clearRect(0, 0, W, H);
      ctx.strokeStyle = c.tree; ctx.lineCap = "round";
      for (var i = 0; i < trees.length; i++) drawBranch(trees[i].x, H, 46 * trees[i].scale, -Math.PI / 2, 7, 0.45);
      for (var j = 0; j < motes.length; j++) {
        var m = motes[j];
        ctx.beginPath(); ctx.arc(m.x, m.y, m.r, 0, Math.PI * 2);
        ctx.fillStyle = "rgba(" + c.mote[0] + "," + c.mote[1] + "," + c.mote[2] + "," + (m.a * c.moteA).toFixed(3) + ")";
        ctx.fill();
      }
    }

    // Pause when the hero scrolls out of view (perf + battery).
    var running = true;
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) {
            if (!running && !reduceMotion) { running = true; raf = requestAnimationFrame(frame); }
          } else {
            running = false; if (raf) { cancelAnimationFrame(raf); raf = null; }
          }
        });
      }, { threshold: 0 }).observe(canvas);
    }

    var resizeTimer;
    window.addEventListener("resize", function () {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(function () {
        resize(); initMotes();
        if (reduceMotion) drawStatic();
      }, 180);
    });

    start();
  })();
})();
