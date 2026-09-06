/* CS2 Config Docs — shell behaviour: theme, TOC, scroll-spy, copy buttons,
   mobile drawer and a cross-page search modal. No dependencies, no build step. */
(function () {
  'use strict';

  var PAGES = [
    { url: 'index.html', name: 'Config reference' },
    { url: 'scancodes.html', name: 'Scancodes' },
    { url: 'dead-commands.html', name: 'Dead commands' }
  ];
  var main = document.querySelector('main');
  var here = (location.pathname.split('/').pop() || 'index.html');

  /* ---------- theme ---------- */
  var root = document.documentElement;
  try {
    var saved = localStorage.getItem('theme');
    if (saved) root.setAttribute('data-theme', saved);
  } catch (e) {}
  var themeBtn = document.getElementById('themeBtn');
  if (themeBtn) themeBtn.addEventListener('click', function () {
    var dark = matchMedia('(prefers-color-scheme: dark)').matches;
    var cur = root.getAttribute('data-theme') || (dark ? 'dark' : 'light');
    var next = cur === 'dark' ? 'light' : 'dark';
    root.setAttribute('data-theme', next);
    try { localStorage.setItem('theme', next); } catch (e) {}
  });

  /* ---------- mobile drawer ---------- */
  var sidebar = document.getElementById('sidebar');
  var scrim = document.getElementById('scrim');
  function closeDrawer() {
    if (sidebar) sidebar.classList.remove('open');
    if (scrim) scrim.hidden = true;
  }
  var menuBtn = document.getElementById('menuBtn');
  if (menuBtn) menuBtn.addEventListener('click', function () {
    var open = sidebar.classList.toggle('open');
    if (scrim) scrim.hidden = !open;
  });
  if (scrim) scrim.addEventListener('click', closeDrawer);
  if (sidebar) sidebar.addEventListener('click', function (e) {
    if (e.target.tagName === 'A') closeDrawer();
  });

  /* ---------- slugs + heading anchors ---------- */
  function slug(t) {
    return t.toLowerCase().replace(/[^\w\s-]/g, '').trim().replace(/\s+/g, '-').slice(0, 60);
  }
  var headings = main ? [].slice.call(main.querySelectorAll('section h2, section h3')) : [];
  headings.forEach(function (h) {
    if (!h.id) h.id = slug(h.textContent);
    var a = document.createElement('a');
    a.className = 'anchor';
    a.href = '#' + h.id;
    a.textContent = '#';
    a.setAttribute('aria-label', 'Link to this heading');
    h.appendChild(a);
  });

  /* ---------- wrap tables so wide ones scroll ---------- */
  if (main) [].slice.call(main.querySelectorAll('table')).forEach(function (t) {
    if (t.parentElement.classList.contains('table-wrap')) return;
    var w = document.createElement('div');
    w.className = 'table-wrap';
    t.parentNode.insertBefore(w, t);
    w.appendChild(t);
  });

  /* ---------- table filters (any input.filter filters table.cmdtable) ---------- */
  [].slice.call(document.querySelectorAll('input.filter')).forEach(function (inp) {
    inp.addEventListener('input', function () {
      var q = inp.value.toLowerCase().trim();
      [].slice.call(document.querySelectorAll('table.cmdtable')).forEach(function (t) {
        var shown = 0;
        [].slice.call(t.querySelectorAll('tbody tr')).forEach(function (row) {
          var hit = !q || row.textContent.toLowerCase().indexOf(q) > -1;
          row.classList.toggle('hidden', !hit);
          if (hit) shown++;
        });
        var box = t.closest('.table-wrap') || t;
        box.classList.toggle('hidden', shown === 0);
        var h = box.previousElementSibling;
        if (h && h.tagName === 'H3') h.classList.toggle('hidden', shown === 0);
      });
    });
  });

  /* ---------- copy buttons on code blocks ---------- */
  var COPY = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/></svg>';
  if (main) [].slice.call(main.querySelectorAll('pre')).forEach(function (pre) {
    var wrap = document.createElement('div');
    wrap.className = 'code-wrap';
    pre.parentNode.insertBefore(wrap, pre);
    wrap.appendChild(pre);
    var b = document.createElement('button');
    b.className = 'copy-btn';
    b.type = 'button';
    b.title = 'Copy';
    b.setAttribute('aria-label', 'Copy code');
    b.innerHTML = COPY;
    b.addEventListener('click', function () {
      navigator.clipboard.writeText(pre.innerText).then(function () {
        b.classList.add('done');
        b.textContent = '✓';
        setTimeout(function () { b.classList.remove('done'); b.innerHTML = COPY; }, 1200);
      });
    });
    wrap.appendChild(b);
  });

  /* ---------- on this page ---------- */
  var tocNav = document.querySelector('.toc nav');
  var tocLinks = [];
  if (tocNav) {
    headings.forEach(function (h) {
      var a = document.createElement('a');
      a.href = '#' + h.id;
      a.textContent = h.textContent.replace(/#$/, '').replace(/^\d+\s*/, '').trim();
      if (h.tagName === 'H3') a.className = 'lvl3';
      tocNav.appendChild(a);
      tocLinks.push(a);
    });
    if (!headings.length) document.querySelector('.toc').style.display = 'none';
  }

  /* ---------- scroll-spy for TOC + sidebar ---------- */
  var sideLinks = sidebar ? [].slice.call(sidebar.querySelectorAll('a[href^="#"]')) : [];
  var targets = headings.concat(main ? [].slice.call(main.querySelectorAll('section[id]')) : []);
  function spy() {
    var best = null, bestTop = -Infinity, line = 120;
    headings.forEach(function (h) {
      var top = h.getBoundingClientRect().top;
      if (top < line && top > bestTop) { bestTop = top; best = h; }
    });
    if (!best && headings.length) best = headings[0];
    if (!best) return;
    tocLinks.forEach(function (a) {
      a.classList.toggle('active', a.getAttribute('href') === '#' + best.id);
    });
    var sec = best.closest('section');
    var ids = [best.id];
    if (sec && sec.id) ids.push(sec.id);
    sideLinks.forEach(function (a) {
      a.classList.toggle('active', ids.indexOf(a.getAttribute('href').slice(1)) > -1);
    });
    var act = tocNav && tocNav.querySelector('a.active');
    if (act) {
      var t = act.offsetTop, box = act.parentElement.parentElement;
      if (t < box.scrollTop || t > box.scrollTop + box.clientHeight - 40) box.scrollTop = t - 80;
    }
  }
  var ticking = false;
  addEventListener('scroll', function () {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(function () { spy(); ticking = false; });
  }, { passive: true });
  spy();

  /* ---------- search ---------- */
  var modal = document.getElementById('searchModal');
  var input = modal && modal.querySelector('input');
  var results = modal && modal.querySelector('.results');
  var index = null, sel = 0, rows = [];

  function indexDoc(doc, page) {
    var out = [];
    var secs = doc.querySelectorAll('main section');
    [].slice.call(secs).forEach(function (sec) {
      [].slice.call(sec.querySelectorAll('h2, h3')).forEach(function (h) {
        var title = h.textContent.replace(/#$/, '').trim();
        var id = h.id || slug(title);
        var body = '';
        var n = h.nextElementSibling;
        while (n && !/^H[23]$/.test(n.tagName)) { body += ' ' + n.textContent; n = n.nextElementSibling; }
        out.push({ page: page.name, url: page.url + '#' + id, title: title, text: body.replace(/\s+/g, ' ').trim() });
      });
      // one entry per table row, so convar and scancode names are findable
      [].slice.call(sec.querySelectorAll('tbody tr')).forEach(function (tr) {
        var key = tr.cells[0] ? tr.cells[0].textContent.trim() : '';
        if (!key || key.length > 60) return;
        var sid = sec.id || '';
        out.push({
          page: page.name, url: page.url + (sid ? '#' + sid : ''), title: key,
          text: tr.textContent.replace(/\s+/g, ' ').trim().slice(0, 200)
        });
      });
    });
    return out;
  }

  function buildIndex() {
    if (index) return Promise.resolve(index);
    var me = PAGES.filter(function (p) { return p.url === here; })[0] || PAGES[0];
    index = indexDoc(document, me);
    return Promise.all(PAGES.filter(function (p) { return p.url !== me.url; }).map(function (p) {
      return fetch(p.url).then(function (r) { return r.text(); }).then(function (html) {
        var d = new DOMParser().parseFromString(html, 'text/html');
        [].slice.call(d.querySelectorAll('main section h2, main section h3')).forEach(function (h) {
          if (!h.id) h.id = slug(h.textContent);
        });
        index = index.concat(indexDoc(d, p));
      }).catch(function () {});
    })).then(function () { return index; });
  }

  function esc(s) { return s.replace(/[&<>]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]; }); }
  function hl(s, q) {
    var i = s.toLowerCase().indexOf(q);
    if (i < 0) return esc(s);
    return esc(s.slice(0, i)) + '<mark>' + esc(s.slice(i, i + q.length)) + '</mark>' + esc(s.slice(i + q.length));
  }

  function render(q) {
    q = q.toLowerCase().trim();
    rows = [];
    if (!q) {
      results.innerHTML = '<div class="search-empty">Search headings, convars, scancodes and dead commands.</div>';
      return;
    }
    if (!index) {
      results.innerHTML = '<div class="search-empty">Indexing…</div>';
      return;
    }
    var hits = (index || []).map(function (e) {
      var ti = e.title.toLowerCase().indexOf(q);
      var bi = e.text.toLowerCase().indexOf(q);
      if (ti < 0 && bi < 0) return null;
      return { e: e, score: ti === 0 ? 0 : ti > 0 ? 1 : 2 };
    }).filter(Boolean).sort(function (a, b) { return a.score - b.score; }).slice(0, 30);

    if (!hits.length) {
      results.innerHTML = '<div class="search-empty">No match for “' + esc(q) + '”.</div>';
      return;
    }
    results.innerHTML = hits.map(function (h, i) {
      var e = h.e;
      var bi = e.text.toLowerCase().indexOf(q);
      var snip = bi < 0 ? '' : e.text.slice(Math.max(0, bi - 40), bi + 90);
      return '<a href="' + e.url + '" class="' + (i === 0 ? 'sel' : '') + '">' +
        '<span class="r-title">' + hl(e.title, q) + '</span>' +
        '<span class="r-path">' + esc(e.page) + '</span>' +
        (snip ? '<span class="r-snip">' + hl(snip, q) + '</span>' : '') + '</a>';
    }).join('');
    rows = [].slice.call(results.querySelectorAll('a'));
    sel = 0;
  }

  function openSearch() {
    if (!modal) return;
    modal.hidden = false;
    if (scrim) scrim.hidden = false;
    input.value = '';
    render('');
    input.focus();
    buildIndex().then(function () { if (!modal.hidden && input.value) render(input.value); });
  }
  function closeSearch() {
    if (!modal) return;
    modal.hidden = true;
    if (scrim && !(sidebar && sidebar.classList.contains('open'))) scrim.hidden = true;
  }

  var searchBtn = document.getElementById('searchBtn');
  if (searchBtn) searchBtn.addEventListener('click', openSearch);
  if (modal) {
    modal.addEventListener('click', function (e) { if (e.target === modal) closeSearch(); });
    input.addEventListener('input', function () { render(input.value); });
    input.addEventListener('keydown', function (e) {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        if (!rows.length) return;
        rows[sel].classList.remove('sel');
        sel = (sel + (e.key === 'ArrowDown' ? 1 : rows.length - 1)) % rows.length;
        rows[sel].classList.add('sel');
        rows[sel].scrollIntoView({ block: 'nearest' });
      } else if (e.key === 'Enter' && rows.length) {
        e.preventDefault();
        location.href = rows[sel].getAttribute('href');
        closeSearch();
      }
    });
  }
  addEventListener('keydown', function (e) {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); openSearch(); }
    else if (e.key === '/' && !/^(INPUT|TEXTAREA)$/.test(document.activeElement.tagName)) { e.preventDefault(); openSearch(); }
    else if (e.key === 'Escape') { closeSearch(); closeDrawer(); }
  });
})();
