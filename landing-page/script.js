/* Wren landing page — gentle motion, respectful of Reduce Motion. */
(function () {
  'use strict';

  var reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ---------- nav scroll state + progress bar ---------- */
  var nav = document.getElementById('site-nav');
  var progress = document.getElementById('scroll-progress');

  function onScroll() {
    var y = window.scrollY || window.pageYOffset;
    nav.classList.toggle('scrolled', y > 12);
    var max = document.documentElement.scrollHeight - window.innerHeight;
    progress.style.width = (max > 0 ? Math.min(100, (y / max) * 100) : 0) + '%';
  }
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  /* ---------- reveal on scroll ---------- */
  var revealEls = document.querySelectorAll('.reveal, .pulse-divider');
  if ('IntersectionObserver' in window && !reducedMotion) {
    var revealObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          revealObserver.unobserve(entry.target);
        }
      });
    }, { threshold: 0.12, rootMargin: '0px 0px -6% 0px' });
    revealEls.forEach(function (el) { revealObserver.observe(el); });
  } else {
    revealEls.forEach(function (el) { el.classList.add('is-visible'); });
  }

  /* ---------- animated counters ---------- */
  function easeOutCubic(t) { return 1 - Math.pow(1 - t, 3); }

  function animateCounter(el) {
    var target = parseFloat(el.getAttribute('data-count-to'));
    var decimals = parseInt(el.getAttribute('data-decimals') || '0', 10);
    var prefix = el.getAttribute('data-prefix') || '';
    var duration = 1400;
    var start = null;

    if (reducedMotion) {
      el.textContent = prefix + target.toFixed(decimals);
      return;
    }
    function step(ts) {
      if (!start) start = ts;
      var t = Math.min(1, (ts - start) / duration);
      var value = target * easeOutCubic(t);
      el.textContent = prefix + value.toFixed(decimals);
      if (t < 1) requestAnimationFrame(step);
    }
    requestAnimationFrame(step);
  }

  var counters = document.querySelectorAll('[data-count-to]');
  if ('IntersectionObserver' in window) {
    var counterObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          animateCounter(entry.target);
          counterObserver.unobserve(entry.target);
        }
      });
    }, { threshold: 0.5 });
    counters.forEach(function (el) { counterObserver.observe(el); });
  } else {
    counters.forEach(animateCounter);
  }

  /* ---------- drifting charts ---------- */
  function smoothPath(points, width, height) {
    if (!points.length) return '';
    var stepX = width / (points.length - 1);
    function x(i) { return i * stepX; }
    var d = 'M 0,' + points[0].y.toFixed(2);
    for (var i = 0; i < points.length - 1; i++) {
      var p0 = points[Math.max(0, i - 1)].y;
      var p1 = points[i].y;
      var p2 = points[i + 1].y;
      var p3 = points[Math.min(points.length - 1, i + 2)].y;
      var c1x = x(i) + stepX / 3;
      var c1y = p1 + (p2 - p0) / 6;
      var c2x = x(i + 1) - stepX / 3;
      var c2y = p2 - (p3 - p1) / 6;
      d += ' C ' + c1x.toFixed(2) + ',' + c1y.toFixed(2) + ' ' +
           c2x.toFixed(2) + ',' + c2y.toFixed(2) + ' ' +
           x(i + 1).toFixed(2) + ',' + p2.toFixed(2);
    }
    return d;
  }

  function DriftChart(svg) {
    this.svg = svg;
    this.line = svg.querySelector('.chart-line');
    this.area = svg.querySelector('.chart-area');
    var box = svg.getAttribute('viewBox').split(' ').map(Number);
    this.w = box[2];
    this.h = box[3];
    this.min = parseFloat(svg.getAttribute('data-min') || '0');
    this.max = parseFloat(svg.getAttribute('data-max') || '100');
    this.count = 26;
    this.points = [];
    var mid = (this.min + this.max) / 2;
    for (var i = 0; i < this.count; i++) {
      var v = mid + (Math.random() - 0.5) * (this.max - this.min) * 0.4;
      this.points.push({ value: v, target: v });
    }
    this.render(true);
  }

  DriftChart.prototype.nextValue = function () {
    var last = this.points[this.points.length - 1].target;
    var range = this.max - this.min;
    var mid = (this.min + this.max) / 2;
    var v = last + (Math.random() - 0.5) * range * 0.28;
    v += (mid - v) * 0.12; /* gentle pull to centre */
    return Math.max(this.min, Math.min(this.max, v));
  };

  DriftChart.prototype.toY = function (value) {
    var t = (value - this.min) / (this.max - this.min);
    return this.h - (t * (this.h * 0.82) + this.h * 0.09);
  };

  DriftChart.prototype.tick = function () {
    this.points.shift();
    var target = this.nextValue();
    this.points.push({ value: target, target: target });
  };

  DriftChart.prototype.render = function (snap) {
    var self = this;
    var pts = this.points.map(function (p) {
      if (snap) p.value = p.target;
      return { y: self.toY(p.value) };
    });
    var d = smoothPath(pts, this.w, this.h);
    this.line.setAttribute('d', d);
    if (this.area) {
      this.area.setAttribute('d', d + ' L ' + this.w + ',' + this.h + ' L 0,' + this.h + ' Z');
    }
  };

  var charts = [];
  document.querySelectorAll('.drift-chart').forEach(function (svg) {
    charts.push(new DriftChart(svg));
  });

  if (!reducedMotion && charts.length) {
    setInterval(function () {
      charts.forEach(function (c) { c.tick(); });
    }, 1000);

    (function frame() {
      charts.forEach(function (c) {
        var moving = false;
        c.points.forEach(function (p) {
          var diff = p.target - p.value;
          if (Math.abs(diff) > 0.01) {
            p.value += diff * 0.06;
            moving = true;
          }
        });
        if (moving) c.render(false);
      });
      requestAnimationFrame(frame);
    })();
  }

  /* ---------- live numbers ---------- */
  function groupDigits(n) {
    return n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  }

  var liveNums = [];
  document.querySelectorAll('.live-num').forEach(function (el) {
    liveNums.push({
      el: el,
      base: parseFloat(el.getAttribute('data-base') || '0'),
      jitter: parseFloat(el.getAttribute('data-jitter') || '0'),
      min: parseFloat(el.getAttribute('data-min') || '-Infinity'),
      max: parseFloat(el.getAttribute('data-max') || 'Infinity'),
      decimals: parseInt(el.getAttribute('data-decimals') || '0', 10),
      group: el.getAttribute('data-group') === '1'
    });
  });

  function refreshLiveNums() {
    liveNums.forEach(function (n) {
      if (n.jitter <= 0) return;
      var v = n.base + (Math.random() - 0.5) * 2 * n.jitter;
      v = Math.max(n.min, Math.min(n.max, v));
      var text = n.group ? groupDigits(Math.round(v)) : v.toFixed(n.decimals);
      if (n.el.textContent !== text) {
        n.el.textContent = text;
        /* soft colour flash via transition (no keyframes) */
        n.el.style.transition = 'none';
        n.el.style.color = '#1f7fb8';
        void n.el.offsetWidth;
        n.el.style.transition = 'color 1.1s ease';
        n.el.style.color = '';
      }
    });
  }
  if (!reducedMotion && liveNums.length) {
    setInterval(refreshLiveNums, 2000);
  }

  /* ---------- live bars ---------- */
  var liveBars = [];
  document.querySelectorAll('.live-bar').forEach(function (el) {
    liveBars.push({
      el: el,
      base: parseFloat(el.getAttribute('data-base') || '20'),
      jitter: parseFloat(el.getAttribute('data-jitter') || '8'),
      min: parseFloat(el.getAttribute('data-min') || '2'),
      max: parseFloat(el.getAttribute('data-max') || '95')
    });
  });
  if (!reducedMotion && liveBars.length) {
    setInterval(function () {
      liveBars.forEach(function (b) {
        var v = b.base + (Math.random() - 0.5) * 2 * b.jitter;
        v = Math.max(b.min, Math.min(b.max, v));
        b.el.style.width = v.toFixed(1) + '%';
      });
    }, 2200);
  }

  /* ---------- hero window tilt ---------- */
  var tiltWrap = document.getElementById('hero-tilt');
  var heroWindow = document.getElementById('hero-window');
  if (tiltWrap && heroWindow && !reducedMotion && window.matchMedia('(pointer: fine)').matches) {
    tiltWrap.addEventListener('mousemove', function (e) {
      var rect = tiltWrap.getBoundingClientRect();
      var px = (e.clientX - rect.left) / rect.width - 0.5;
      var py = (e.clientY - rect.top) / rect.height - 0.5;
      heroWindow.style.setProperty('--ry', (px * 5).toFixed(2) + 'deg');
      heroWindow.style.setProperty('--rx', (-py * 4).toFixed(2) + 'deg');
    });
    tiltWrap.addEventListener('mouseleave', function () {
      heroWindow.style.setProperty('--rx', '0deg');
      heroWindow.style.setProperty('--ry', '0deg');
    });
  }

  /* ---------- menu bar demo ---------- */
  var menubarToggle = document.getElementById('menubar-toggle');
  var menubarPopup = document.getElementById('menubar-popup');
  if (menubarToggle && menubarPopup) {
    menubarToggle.addEventListener('click', function (e) {
      e.stopPropagation();
      var open = menubarPopup.classList.toggle('is-open');
      menubarToggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
    document.addEventListener('click', function (e) {
      if (!menubarPopup.contains(e.target)) {
        menubarPopup.classList.remove('is-open');
        menubarToggle.setAttribute('aria-expanded', 'false');
      }
    });
    window.addEventListener('scroll', function () {
      menubarPopup.classList.remove('is-open');
      menubarToggle.setAttribute('aria-expanded', 'false');
    }, { passive: true });
    /* open once briefly when it scrolls into view, so visitors notice it */
    if ('IntersectionObserver' in window && !reducedMotion) {
      var popupSeen = false;
      var popupObserver = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting && !popupSeen) {
            popupSeen = true;
            setTimeout(function () {
              menubarPopup.classList.add('is-open');
              menubarToggle.setAttribute('aria-expanded', 'true');
              setTimeout(function () {
                menubarPopup.classList.remove('is-open');
                menubarToggle.setAttribute('aria-expanded', 'false');
              }, 3200);
            }, 600);
            popupObserver.disconnect();
          }
        });
      }, { threshold: 0.6 });
      popupObserver.observe(menubarPopup.parentElement);
    }
  }

  /* menu bar clock */
  var clock = document.getElementById('menubar-clock');
  if (clock) {
    var updateClock = function () {
      var d = new Date();
      var h = d.getHours();
      var m = d.getMinutes();
      clock.textContent = ((h % 12) || 12) + ':' + (m < 10 ? '0' : '') + m;
    };
    updateClock();
    setInterval(updateClock, 20000);
  }

  /* ---------- history tabs ---------- */
  var histTabs = document.querySelectorAll('.hist-tab');
  var histPaths = document.querySelectorAll('.hist-path');
  histTabs.forEach(function (tab) {
    tab.addEventListener('click', function () {
      var index = parseInt(tab.getAttribute('data-hist'), 10);
      histTabs.forEach(function (t) {
        t.classList.remove('is-active');
        t.setAttribute('aria-selected', 'false');
      });
      tab.classList.add('is-active');
      tab.setAttribute('aria-selected', 'true');
      histPaths.forEach(function (p, i) {
        p.classList.toggle('is-active', i === index);
      });
    });
  });

  /* ---------- wiki typing loop ---------- */
  var wikiTyped = document.getElementById('wiki-typed');
  var wikiResult = document.getElementById('wiki-result');
  var wikiEntries = [
    { term: 'kernel_task', text: 'the kernel\u2019s own process. It often uses CPU on purpose to manage heat by throttling the machine. Usually normal, always on your side.' },
    { term: 'WindowServer', text: 'draws everything you see on screen. It rises with lots of windows, animations, or external displays. Normal.' },
    { term: 'mds_stores', text: 'Spotlight\u2019s indexer. Busy after big file changes or a first setup \u2014 it settles down on its own.' },
    { term: 'launchd', text: 'starts and manages nearly every other process. If it looks busy, something it launched is busy.' }
  ];
  if (wikiTyped && wikiResult && !reducedMotion) {
    var wikiIndex = 0;
    var typeState = { char: 0, deleting: false };

    function setResult(entry) {
      wikiResult.innerHTML = '<b>' + entry.term + '</b> \u2014 ' + entry.text;
    }

    function wikiLoop() {
      var entry = wikiEntries[wikiIndex];
      if (!typeState.deleting) {
        typeState.char++;
        wikiTyped.textContent = entry.term.slice(0, typeState.char);
        if (typeState.char >= entry.term.length) {
          setResult(entry);
          wikiResult.classList.remove('is-switching');
          typeState.deleting = true;
          setTimeout(wikiLoop, 3400);
          return;
        }
        setTimeout(wikiLoop, 70 + Math.random() * 90);
      } else {
        wikiResult.classList.add('is-switching');
        typeState.char--;
        wikiTyped.textContent = entry.term.slice(0, Math.max(0, typeState.char));
        if (typeState.char <= 0) {
          typeState.deleting = false;
          wikiIndex = (wikiIndex + 1) % wikiEntries.length;
          setTimeout(wikiLoop, 500);
          return;
        }
        setTimeout(wikiLoop, 34);
      }
    }
    setTimeout(wikiLoop, 1200);
  }

  /* ---------- wiki section demo ---------- */
  var wdTyped = document.getElementById('wd-typed');
  var wdRows = document.getElementById('wd-rows');
  var wdDetail = document.getElementById('wd-detail');
  var wdCount = document.getElementById('wd-count');
  if (wdTyped && wdRows && wdDetail && wdCount && !reducedMotion) {
    var wdSafety = {
      safe: { label: 'Safe to quit', cls: 'wd-chip-safe', note: 'You can quit this and things will be fine. It comes back when it is needed.' },
      depends: { label: 'Depends', cls: 'wd-chip-depends', note: 'Quitting this may pause a task rather than break anything.' },
      leave: { label: 'Leave this one alone', cls: 'wd-chip-leave', note: 'Quitting this would interrupt something important, or stop your Mac working properly.' }
    };
    var wdScenarios = [
      {
        query: 'fan loud',
        matches: [
          { name: 'kernel_task', category: 'Part of macOS' },
          { name: 'WindowServer', category: 'Part of macOS' }
        ],
        entry: {
          name: 'kernel_task', category: 'Part of macOS', safety: 'leave',
          summary: 'The core of macOS itself. A high number here is usually macOS protecting itself from heat.',
          detail: 'This is the operating system rather than an app. When your Mac gets warm, macOS deliberately makes kernel_task busy so other things cannot use the processor \u2014 it is easing off the throttle, not causing the heat. High kernel_task beside a warm machine points at something else working hard. It cannot be quit.',
          aliases: 'kernel task \u00A0\u00B7\u00A0 kerneltask',
          knownFor: 'very high cpu \u00A0\u00B7\u00A0 fan on \u00A0\u00B7\u00A0 mac is hot \u00A0\u00B7\u00A0 throttling'
        }
      },
      {
        query: 'spotlight',
        matches: [
          { name: 'mds_stores', category: 'Background service' },
          { name: 'mdworker_shared', category: 'Background service' }
        ],
        entry: {
          name: 'mds_stores', category: 'Background service', safety: 'depends',
          summary: 'Spotlight, building the index that makes search work.',
          detail: 'To find files instantly, macOS keeps an index of everything on your disk. This process writes that index. It works hard right after a macOS update, a large file copy, or connecting a big drive, then goes quiet. Let it finish \u2014 interrupting it just means it starts again.',
          aliases: 'mds stores \u00A0\u00B7\u00A0 mds \u00A0\u00B7\u00A0 spotlight indexing',
          knownFor: 'spotlight slow \u00A0\u00B7\u00A0 high cpu after update \u00A0\u00B7\u00A0 search not finding files'
        }
      },
      {
        query: 'icloud',
        matches: [
          { name: 'cloudd', category: 'Sync & cloud' },
          { name: 'bird', category: 'Sync & cloud' },
          { name: 'fileproviderd', category: 'Sync & cloud' }
        ],
        entry: {
          name: 'cloudd', category: 'Sync & cloud', safety: 'depends',
          summary: 'iCloud syncing \u2014 keeping your documents, photos and settings up to date.',
          detail: 'This moves data between your Mac and iCloud. It gets busy after you add a lot of files, or when you sign in on a new device and everything has to catch up.',
          aliases: 'cloud d \u00A0\u00B7\u00A0 icloud sync',
          knownFor: 'icloud \u00A0\u00B7\u00A0 photos uploading \u00A0\u00B7\u00A0 background data'
        }
      },
      {
        query: 'tabs',
        matches: [
          { name: 'Safari Web Content', category: 'Apple app' }
        ],
        entry: {
          name: 'Safari Web Content', category: 'Apple app', safety: 'safe',
          summary: 'One of the pieces Safari runs underneath itself \u2014 usually a group of browser tabs.',
          detail: 'Safari splits itself into several processes so one misbehaving tab cannot take the rest down. Each of these holds a set of tabs. A large memory number almost always means many tabs are open. Quitting closes those tabs; Safari offers to reopen them next time.',
          aliases: 'safari helper \u00A0\u00B7\u00A0 webkit webcontent \u00A0\u00B7\u00A0 safari tab',
          knownFor: 'high memory \u00A0\u00B7\u00A0 many tabs \u00A0\u00B7\u00A0 safari slow',
          identifier: 'com.apple.WebKit.WebContent'
        }
      }
    ];
    var wdIndex = 0;
    var wdChar = wdTyped.textContent.length;
    var wdPhase = 'hold';

    function wdDetailHTML(e) {
      var s = wdSafety[e.safety];
      var html = '<p class="wd-name">' + e.name + '</p>' +
        '<p class="wd-summary">' + e.summary + '</p>' +
        '<div class="wd-chips"><span class="wd-chip">' + e.category + '</span>' +
        '<span class="wd-chip ' + s.cls + '">' + s.label + '</span></div>' +
        '<p class="wd-text">' + e.detail + '</p>' +
        '<div class="wd-rule"></div>' +
        '<p class="wd-note">' + s.note + '</p>';
      if (e.aliases) html += '<div class="wd-meta"><span>Also called</span><p>' + e.aliases + '</p></div>';
      if (e.knownFor) html += '<div class="wd-meta"><span>Known for</span><p>' + e.knownFor + '</p></div>';
      if (e.identifier) html += '<div class="wd-meta"><span>Identifier</span><p class="wd-mono">' + e.identifier + '</p></div>';
      return html;
    }

    function wdSwap(sc) {
      wdRows.classList.add('is-switching');
      wdDetail.classList.add('is-switching');
      setTimeout(function () {
        wdCount.textContent = sc.matches.length + ' matching';
        wdRows.innerHTML = sc.matches.map(function (m, i) {
          return '<div class="wd-row' + (i === 0 ? ' is-selected' : '') + '"><b>' + m.name + '</b><span>' + m.category + '</span></div>';
        }).join('');
        wdDetail.innerHTML = wdDetailHTML(sc.entry);
        wdRows.classList.remove('is-switching');
        wdDetail.classList.remove('is-switching');
      }, 300);
    }

    function wdStep() {
      if (wdPhase === 'hold') {
        wdPhase = 'deleting';
        setTimeout(wdStep, 4600);
        return;
      }
      if (wdPhase === 'deleting') {
        var current = wdScenarios[wdIndex];
        wdChar--;
        wdTyped.textContent = current.query.slice(0, Math.max(0, wdChar));
        if (wdChar <= 0) {
          wdPhase = 'typing';
          wdIndex = (wdIndex + 1) % wdScenarios.length;
          setTimeout(wdStep, 450);
        } else {
          setTimeout(wdStep, 28);
        }
        return;
      }
      var next = wdScenarios[wdIndex];
      wdChar++;
      wdTyped.textContent = next.query.slice(0, wdChar);
      if (wdChar >= next.query.length) {
        wdSwap(next);
        wdPhase = 'hold';
        setTimeout(wdStep, 0);
      } else {
        setTimeout(wdStep, 70 + Math.random() * 85);
      }
    }
    setTimeout(wdStep, 3400);
  }

  /* ---------- apps card shuffle ---------- */
  var shuffleGroup = document.querySelector('[data-shuffle]');
  if (shuffleGroup && !reducedMotion) {
    var rows = Array.prototype.slice.call(shuffleGroup.querySelectorAll('.fc-app-row'));
    setInterval(function () {
      rows.forEach(function (row) {
        var bar = row.querySelector('.app-bar i');
        var label = row.querySelector('b');
        var current = parseFloat(label.textContent);
        var v = Math.max(1, Math.min(64, current + (Math.random() - 0.5) * 10));
        bar.style.width = (v * 1.5).toFixed(0) + '%';
        label.textContent = v.toFixed(0) + '%';
      });
    }, 2600);
  }

  /* ---------- settings segmented control ---------- */
  var seg = document.querySelector('[data-seg]');
  if (seg) {
    var thumb = seg.querySelector('.seg-thumb');
    var segBtns = seg.querySelectorAll('.seg-btn');
    function moveThumb(index) {
      thumb.style.transform = 'translateX(' + index * 100 + '%)';
    }
    segBtns.forEach(function (btn, i) {
      if (btn.classList.contains('is-active')) moveThumb(i);
      btn.addEventListener('click', function () {
        segBtns.forEach(function (b) { b.classList.remove('is-active'); });
        btn.classList.add('is-active');
        moveThumb(i);
      });
    });
  }

  /* ---------- toggles ---------- */
  document.querySelectorAll('.switch').forEach(function (sw) {
    function flip() {
      var on = sw.classList.toggle('is-on');
      sw.setAttribute('aria-checked', on ? 'true' : 'false');
    }
    sw.addEventListener('click', flip);
    sw.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        flip();
      }
    });
  });

  /* ---------- accordion: one open at a time ---------- */
  var accs = document.querySelectorAll('#answers .acc');
  accs.forEach(function (acc) {
    acc.addEventListener('toggle', function () {
      if (acc.open) {
        accs.forEach(function (other) {
          if (other !== acc) other.open = false;
        });
      }
    });
  });
})();
