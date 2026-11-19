(() => {
  'use strict';

  const MOD = '/data/adb/modules/hostkeeper';
  const VERSION = 'v1.0.6';
  const VERSION_CODE = 7;
  const RULE_MAX = 1000;
  const LEVEL = { green: '🟢', blue: '🔵', yellow: '🟡', orange: '🟠', red: '🔴' };
  const STEPS = [
    ['download', '⬇️', '下载'],
    ['verify', '🔍', '校验'],
    ['optimize', '🧹', '优化'],
    ['install', '📦', '安装']
  ];
  const PHASE_TEXT = {
    prepare: '⏳ 准备中…',
    check: '🔎 正在检查更新…',
    download: '⬇️ 下载中…',
    verify: '🔍 正在校验下载内容…',
    optimize: '🧹 正在清理和优化…',
    install: '📦 正在安装 hosts 文件…',
    finish: '✨ 正在收尾…'
  };
  const ADDON_GROUPS = [
    ['content', '🎭 内容分类'],
    ['security', '🔐 安全'],
    ['tracker', '📱 设备与应用追踪'],
    ['custom', '🔗 自定义列表']
  ];
  const ADDON_WARN = {
    dns: '🔐 加密 DNS 绕过会拦截公共 DNS-over-HTTPS 服务器，让浏览器和应用回退到系统解析器。你的 Android 私人 DNS 提供商仍会自动保持可用。',
    heavy: '🐘 威胁情报列表非常大。在某些 ROM 上，超过一百万条的 hosts 文件会让 DNS 查询变慢。',
    breaks: '👥 社交网络列表会拦截社交平台本身，相关应用和网站将无法使用。'
  };
  const AUTO_CHOICES = [[0, '关闭'], [1, '每天'], [3, '每 3 天'], [7, '每周']];
  const AUTO_TEXT = { 0: '关闭', 1: '每天', 3: '每 3 天', 7: '每周' };
  const POWER = '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="M12 3.2v8.4" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/><path d="M6.5 6.8a7.7 7.7 0 1 0 11 0" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/></svg>';
  const FAIL = {
    bridge: '❌ HostKeeper 没有响应，请重试。',
    offline: '🔌 本地 WebUI 服务已停止运行。',
    unauthorized: '🔑 当前会话已过期。',
    no_token: '🔑 未找到安全会话。',
    framed: '🚫 HostKeeper 不能在另一个页面中运行。'
  };
  const ERR = {
    empty: '✏️ 请先输入域名。',
    space: '🚫 域名中不能包含空格。',
    wildcard: '🚫 通配符只能用在放行规则开头，例如 *.example.com。',
    wildblock: '🚫 Hosts 文件不能拦截通配符，请输入要拦截的精确域名。',
    port: '🚫 不允许端口和 IPv6 地址，请只输入域名，例如 example.com。',
    ip: '🚫 不允许 IP 地址，请输入域名。',
    invalid: '🚫 这看起来不是有效域名，例如 ads.example.com。'
  };

  const $ = (id) => document.getElementById(id);
  const nf = new Intl.NumberFormat('zh-CN');
  const dateFmt = new Intl.DateTimeFormat('zh-CN', { month: 'short', day: 'numeric', year: 'numeric' });
  const timeFmt = new Intl.DateTimeFormat('zh-CN', { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false });
  const dayFmt = new Intl.DateTimeFormat('zh-CN', { month: 'short', day: 'numeric' });
  const stampFmt = new Intl.DateTimeFormat('zh-CN', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false });

  const store = {
    get(key, session) {
      try {
        return (session ? window.sessionStorage : window.localStorage).getItem(key);
      } catch (e) {
        return null;
      }
    },
    set(key, value, session) {
      try {
        (session ? window.sessionStorage : window.localStorage).setItem(key, value);
      } catch (e) {
        return false;
      }
      return true;
    }
  };

  const S = {
    status: null,
    lists: null,
    refreshing: false,
    rules: { allow: [], block: [] },
    tab: 'allow',
    ruleFilter: '',
    logs: [],
    logSig: '',
    logLevel: 'all',
    op: null,
    busy: false,
    syncBusy: false,
    opView: false,
    seen: Number(store.get('hostkeeper-seq')) || 0,
    speed: { t: 0, b: 0, v: 0 },
    ready: false,
    gate: '',
    addonSel: null,
    lookup: null
  };

  function fmtNum(n) {
    return nf.format(Number(n) || 0);
  }

  function fmtMB(bytes) {
    const b = Math.max(0, Number(bytes) || 0);
    if (b < 1048576) return Math.max(b > 0 ? 1 : 0, Math.round(b / 1024)) + ' KB';
    return (b / 1048576).toFixed(1) + ' MB';
  }

  function fmtDate(sec) {
    return sec ? dateFmt.format(new Date(sec * 1000)) : '未知';
  }

  function plural(n, one, many) {
    return Number(n) === 1 ? one : many;
  }

  function nowSec() {
    return Date.now() / 1000;
  }

  function ago(sec) {
    if (!sec) return '从未';
    const d = Math.max(0, nowSec() - sec);
    if (d < 60) return '刚刚';
    if (d < 3600) return Math.floor(d / 60) + ' 分钟前';
    if (d < 86400) return Math.floor(d / 3600) + ' 小时前';
    const days = Math.floor(d / 86400);
    return days === 1 ? '昨天' : days + ' 天前';
  }

  function logTime(sec) {
    const d = new Date(sec * 1000);
    const now = new Date();
    if (d.toDateString() === now.toDateString()) return timeFmt.format(d);
    return dayFmt.format(d) + ' ' + timeFmt.format(d).slice(0, 5);
  }

  function stripLead(msg) {
    const s = String(msg || '');
    const i = s.indexOf(' ');
    if (i > 0 && i < 6 && !/[A-Za-z0-9]/.test(s.slice(0, i))) return s.slice(i + 1);
    return s;
  }

  function h(tag, props) {
    const el = document.createElement(tag);
    if (props) {
      Object.keys(props).forEach((key) => {
        const v = props[key];
        if (v === null || v === undefined || v === false) return;
        if (key === 'class') el.className = v;
        else if (key === 'text') el.textContent = v;
        else if (key === 'html') el.innerHTML = v;
        else if (key.indexOf('on') === 0) el.addEventListener(key.slice(2), v);
        else el.setAttribute(key, v === true ? '' : v);
      });
    }
    for (let i = 2; i < arguments.length; i++) {
      const c = arguments[i];
      if (c === null || c === undefined || c === false) continue;
      if (Array.isArray(c)) c.forEach((x) => { if (x) el.appendChild(typeof x === 'string' ? document.createTextNode(x) : x); });
      else el.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
    }
    return el;
  }

  function clear(el) {
    while (el.firstChild) el.removeChild(el.firstChild);
    return el;
  }

  function powerIcon() {
    return h('span', { class: 'pw', html: POWER });
  }

  function sk(cls) {
    return h('span', { class: 'sk ' + cls });
  }

  function para(text, cls) {
    return h('p', { class: cls || null, text: text });
  }

  function note(text, kind) {
    return h('div', { class: 'note' + (kind ? ' is-' + kind : ''), text: text });
  }

  const Bridge = (() => {
    const k = ['ksu', 'apatch']
      .map((name) => window[name])
      .find((obj) => obj && typeof obj.exec === 'function') || null;
    let token = '';
    let seq = 0;
    let framed = false;
    if (!k) {
      try {
        framed = window.top !== window.self;
      } catch (e) {
        framed = true;
      }
      const m = /(?:^#|&)t=([0-9a-f]{32})(?:&|$)/.exec(window.location.hash || '');
      if (m) {
        token = m[1];
        store.set('hostkeeper-token', token, true);
        try {
          window.history.replaceState(null, '', window.location.pathname + window.location.search);
        } catch (e) {
          token = m[1];
        }
      } else {
        token = store.get('hostkeeper-token', true) || '';
      }
    }

    function forget(name) {
      try {
        delete window[name];
      } catch (e) {
        window[name] = undefined;
      }
    }

    function exec(command) {
      return new Promise((resolve, reject) => {
        const cb = 'hkcb_' + Date.now().toString(36) + '_' + (seq++).toString(36);
        const timer = setTimeout(() => {
          forget(cb);
          reject(new Error('timeout'));
        }, 120000);
        function done(errno, stdout, stderr) {
          clearTimeout(timer);
          forget(cb);
          resolve({ errno: Number(errno) || 0, stdout: stdout === null || stdout === undefined ? '' : String(stdout), stderr: stderr === null || stderr === undefined ? '' : String(stderr) });
        }
        window[cb] = done;
        try {
          const ret = k.exec(command, JSON.stringify({}), cb);
          if (ret && typeof ret.then === 'function') {
            ret.then((r) => {
              if (r && typeof r === 'object') done(r.errno, r.stdout, r.stderr);
              else done(0, r, '');
            }, (e) => {
              clearTimeout(timer);
              forget(cb);
              reject(e);
            });
          }
        } catch (e) {
          clearTimeout(timer);
          forget(cb);
          reject(e);
        }
      });
    }

    function quote(s) {
      return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    function parse(text) {
      const lines = String(text || '').trim().split('\n');
      for (let i = lines.length - 1; i >= 0; i--) {
        const line = lines[i].trim();
        if (line.charAt(0) !== '{') continue;
        try {
          const o = JSON.parse(line);
          if (o && typeof o.ok === 'boolean') {
            if (!o.data || typeof o.data !== 'object') o.data = {};
            return o;
          }
        } catch (e) {
          continue;
        }
      }
      return null;
    }

    function fail(code) {
      return { ok: false, code: code, message: FAIL[code] || FAIL.bridge, data: {} };
    }

    async function call(cmd, args) {
      const a = (args || []).map((x) => (x === null || x === undefined ? '' : String(x)));
      if (k) {
        let r;
        try {
          r = await exec(['sh', quote(MOD + '/hostkeeper.sh'), quote(cmd)].concat(a.map(quote)).join(' '));
        } catch (e) {
          return fail('bridge');
        }
        return parse(r.stdout) || fail('bridge');
      }
      if (framed) return fail('framed');
      if (!token) return fail('no_token');
      const p = new URLSearchParams();
      p.set('t', token);
      p.set('c', cmd);
      if (a.length > 0) p.set('a', a[0]);
      if (a.length > 1) p.set('b', a[1]);
      if (a.length > 2) p.set('d', a[2]);
      let res;
      try {
        res = await fetch('cgi-bin/api', {
          method: 'POST',
          cache: 'no-store',
          credentials: 'omit',
          referrerPolicy: 'no-referrer',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: p.toString()
        });
      } catch (e) {
        return fail('offline');
      }
      if (res.status === 403) return fail('unauthorized');
      let text = '';
      try {
        text = await res.text();
      } catch (e) {
        return fail('offline');
      }
      return parse(text) || fail(res.ok ? 'bridge' : 'offline');
    }

    return { call: call, mode: k ? 'ksu' : 'http', hasToken: () => !!token, framed: () => framed };
  })();

  async function api(cmd, args) {
    const r = await Bridge.call(cmd, args);
    if (!r.ok && (r.code === 'offline' || r.code === 'unauthorized' || r.code === 'no_token' || r.code === 'framed')) showGate(r.code);
    return r;
  }

  function toast(msg, kind) {
    if (!msg) return;
    const box = $('toasts');
    const t = h('div', { class: 'toast is-' + (kind || 'info'), role: 'status', text: msg });
    box.appendChild(t);
    while (box.children.length > 3) box.removeChild(box.firstChild);
    requestAnimationFrame(() => requestAnimationFrame(() => t.classList.add('is-in')));
    setTimeout(() => {
      t.classList.remove('is-in');
      setTimeout(() => {
        if (t.parentNode) t.parentNode.removeChild(t);
      }, 260);
    }, kind === 'err' ? 5600 : 3800);
  }

  const Modal = (() => {
    const root = $('modal');
    const sheet = $('sheet');
    const icon = $('sheet-icon');
    const title = $('sheet-title');
    const body = $('sheet-body');
    const actions = $('sheet-actions');
    let isOpen = false;
    let dismissible = true;
    let onDismiss = null;
    let closeTimer = 0;
    let lastFocus = null;
    let view = '';

    function render(v) {
      clear(icon);
      if (v.iconNode) icon.appendChild(v.iconNode);
      else icon.textContent = v.icon || '';
      title.textContent = v.title || '';
      clear(body);
      (v.body || []).forEach((n) => { if (n) body.appendChild(n); });
      body.classList.remove('is-swap');
      void body.offsetWidth;
      body.classList.add('is-swap');
      clear(actions);
      (v.actions || []).forEach((a) => {
        const b = h('button', { class: 'btn ' + (a.class || 'btn-ghost'), type: 'button', id: a.id || null });
        if (a.power) b.appendChild(powerIcon());
        b.appendChild(h('span', { class: 'btn-label', text: a.label }));
        if (a.disabled) b.disabled = true;
        b.addEventListener('click', a.onClick);
        actions.appendChild(b);
      });
      actions.hidden = !(v.actions && v.actions.length);
      dismissible = v.dismissible !== false;
      onDismiss = v.onDismiss || null;
      view = v.view || '';
      sheet.scrollTop = 0;
    }

    function show(v) {
      clearTimeout(closeTimer);
      render(v);
      if (!isOpen) {
        isOpen = true;
        lastFocus = document.activeElement;
        root.hidden = false;
        void root.offsetWidth;
        root.classList.add('is-open');
        document.body.classList.add('no-scroll');
        sheet.setAttribute('tabindex', '-1');
        try {
          sheet.focus({ preventScroll: true });
        } catch (e) {
          sheet.focus();
        }
      }
    }

    function close() {
      if (!isOpen) return;
      isOpen = false;
      view = '';
      root.classList.remove('is-open');
      document.body.classList.remove('no-scroll');
      closeTimer = setTimeout(() => { root.hidden = true; }, 270);
      if (lastFocus && typeof lastFocus.focus === 'function') {
        try {
          lastFocus.focus({ preventScroll: true });
        } catch (e) {
          lastFocus = null;
        }
      }
    }

    function dismiss() {
      if (!isOpen || !dismissible) return;
      const f = onDismiss;
      close();
      if (f) f();
    }

    function trap(e) {
      if (!isOpen || e.key !== 'Tab') return;
      const nodes = sheet.querySelectorAll('button:not([disabled]), input:not([disabled]), textarea:not([disabled])');
      if (!nodes.length) {
        e.preventDefault();
        return;
      }
      const first = nodes[0];
      const last = nodes[nodes.length - 1];
      const active = document.activeElement;
      if (e.shiftKey && (active === first || !sheet.contains(active))) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && (active === last || !sheet.contains(active))) {
        e.preventDefault();
        first.focus();
      }
    }

    $('modal-scrim').addEventListener('click', dismiss);
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') dismiss();
      else trap(e);
    });

    return { show: show, close: close, open: () => isOpen, view: () => view };
  })();

  function gotIt() {
    return [{ label: '👌 知道了', class: 'btn-primary', onClick: () => Modal.close() }];
  }

  function confirmBox(o) {
    return new Promise((resolve) => {
      let done = false;
      const finish = (v) => {
        if (done) return;
        done = true;
        resolve(v);
      };
      Modal.show({
        icon: o.icon,
        iconNode: o.iconNode,
        title: o.title,
        body: o.body,
        view: 'confirm',
        onDismiss: () => finish(false),
        actions: [
          { label: '↩️ 暂不', class: 'btn-ghost', onClick: () => { Modal.close(); finish(false); } },
          { label: o.ok, class: o.okClass || 'btn-primary', power: o.power, onClick: () => finish(true) }
        ]
      });
    });
  }

  function showGate(code) {
    if (S.gate === code) return;
    S.gate = code;
    const map = {
      no_token: ['🔑', '需要安全会话', '请从 root 管理器打开 HostKeeper：点击 HostKeeper 模块卡片上的 Action ▶️ 按钮。它会用一次性安全链接启动本地 WebUI。'],
      unauthorized: ['🔑', '会话已过期', '此 WebUI 会话已失效。请点击 root 管理器中 HostKeeper 的 Action ▶️ 按钮重新打开。'],
      offline: ['🔌', 'WebUI 服务已停止', '本地服务在 10 分钟无活动后会自动停止。请点击 root 管理器中 HostKeeper 的 Action ▶️ 按钮重新启动。'],
      framed: ['🚫', '出于安全原因已阻止', 'HostKeeper 不会在另一个页面中运行。请从 HostKeeper 模块卡片的 Action ▶️ 按钮打开。'],
      bridge: ['❌', '无法连接 HostKeeper', '模块没有响应。请确认 HostKeeper 已安装并启用；如果刚安装，请先重启。']
    };
    const m = map[code] || map.bridge;
    $('gate-icon').textContent = m[0];
    $('gate-title').textContent = m[1];
    $('gate-text').textContent = m[2];
    $('gate-retry').hidden = code === 'framed';
    Modal.close();
    $('gate').hidden = false;
  }

  async function retryGate() {
    const btn = $('gate-retry');
    btn.disabled = true;
    const code = S.gate;
    S.gate = '';
    const r = await Bridge.call('ping');
    btn.disabled = false;
    if (r.ok) {
      $('gate').hidden = true;
      if (!S.ready) {
        start();
      } else {
        refreshAll();
      }
    } else {
      showGate(r.code === 'bridge' ? (code || 'bridge') : r.code);
      toast(r.message, 'err');
    }
  }

  async function copyText(text) {
    try {
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(text);
        return true;
      }
    } catch (e) {
      return legacyCopy(text);
    }
    return legacyCopy(text);
  }

  function legacyCopy(text) {
    const ta = h('textarea', { class: 'area', readonly: true, 'aria-hidden': 'true' });
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    ta.style.pointerEvents = 'none';
    document.body.appendChild(ta);
    let ok = false;
    try {
      ta.focus();
      ta.select();
      ta.setSelectionRange(0, text.length);
      ok = document.execCommand('copy');
    } catch (e) {
      ok = false;
    }
    document.body.removeChild(ta);
    return ok;
  }

  function textSheet(o) {
    const ta = h('textarea', { class: 'area', readonly: true, spellcheck: 'false', 'aria-label': o.title });
    ta.value = o.text;
    const hint = h('p', { class: 'fine', text: o.hint || '' });
    Modal.show({
      icon: o.icon,
      title: o.title,
      body: [ta, hint],
      view: 'text',
      actions: [
        { label: '👌 完成', class: 'btn-ghost', onClick: () => Modal.close() },
        {
          label: '📋 复制',
          class: 'btn-primary',
          onClick: async () => {
            const ok = await copyText(o.text);
            if (ok) {
              hint.textContent = '✅ 已复制到剪贴板。';
              hint.className = 'fine is-ok';
            } else {
              ta.focus();
              ta.select();
              hint.textContent = '✏️ 此处无法直接复制，文本已选中，请手动复制。';
              hint.className = 'fine';
            }
          }
        }
      ]
    });
  }

  function stateOf(st) {
    if (!st) return { cls: 'is-wait', e: '⏳', t: '加载中…' };
    if (st.setup === 'pending') return { cls: 'is-wait', e: '⏳', t: '等待初始化' };
    if (st.setup === 'failed') return { cls: 'is-off', e: '❌', t: '初始化失败' };
    if (st.reboot) return { cls: 'is-warn', e: '🟡', t: '需要重启' };
    if (!st.enabled) return { cls: 'is-off', e: '🔴', t: '已停用' };
    if (st.applied === 'overridden') return { cls: 'is-warn', e: '⚠️', t: '被覆盖' };
    if (st.applied === 'inactive') return { cls: 'is-off', e: '🔴', t: '未生效' };
    return { cls: 'is-on', e: '🟢', t: '已启用' };
  }

  function appliedText(a) {
    if (a === 'applied') return ['✅ 已生效', 'is-ok'];
    if (a === 'pending') return ['🟡 尚未生效，需要重启', 'is-warn'];
    if (a === 'overridden') return ['⚠️ 被其他模块覆盖', 'is-warn'];
    if (a === 'inactive') return ['🔴 未生效，重启后激活', 'is-err'];
    return ['ℹ️ 无法检查系统 hosts 文件', ''];
  }

  function staleDaysOf(st) {
    if (!st || st.setup !== 'ready' || !st.updated) return 0;
    return Math.floor((nowSec() - st.updated) / 86400);
  }

  function isStale(st) {
    return !!st && st.setup === 'ready' && st.enabled && staleDaysOf(st) >= (st.staleDays || 7);
  }

  function listName(id) {
    if (S.lists) {
      const all = (S.lists.lists || []).concat(S.lists.addons || []);
      for (let i = 0; i < all.length; i++) if (all[i].id === id) return all[i].name;
    }
    if (S.status && S.status.list === id) return S.status.listName;
    return id || 'your list';
  }

  function findList(id) {
    if (!S.lists || !S.lists.lists) return null;
    for (let i = 0; i < S.lists.lists.length; i++) if (S.lists.lists[i].id === id) return S.lists.lists[i];
    return null;
  }

  function findAddon(id) {
    if (!S.lists || !S.lists.addons) return null;
    for (let i = 0; i < S.lists.addons.length; i++) if (S.lists.addons[i].id === id) return S.lists.addons[i];
    return null;
  }

  function renderPowerSwitch(st) {
    const on = !!st.enabled;
    const tgl = $('act-toggle');
    tgl.setAttribute('aria-checked', on ? 'true' : 'false');
    tgl.setAttribute('aria-label', on ? '关闭拦截' : '开启拦截');
    tgl.title = on ? '关闭拦截' : '开启拦截';
    const ts = $('toggle-state');
    ts.textContent = on ? '开启' : '关闭';
    ts.classList.toggle('is-on', on);
  }

  function renderStatus() {
    const st = S.status;
    if (!st) return;
    const s = stateOf(st);
    const badge = $('badge');
    badge.className = 'badge ' + s.cls;
    $('badge-emoji').textContent = s.e;
    $('badge-text').textContent = s.t;
    $('ver').textContent = st.version || VERSION;
    $('credits-ver').textContent = 'HostKeeper ' + (st.version || VERSION) + ' • 🔒 仅本地运行 • 无遥测 • Inter (SIL OFL 1.1)';

    const alert = $('ribbon-alert');
    const nav = $('ribbon-nav');
    let mode = '';
    if (st.reboot) mode = 'reboot';
    else if (st.setup !== 'ready' && !S.busy) mode = 'setup';
    else if (st.applied === 'inactive' && st.enabled && st.setup === 'ready') mode = 'inactive';
    if (mode) {
      const texts = {
        reboot: ['🟡 重启后生效', '🟡 需要重启'],
        inactive: ['🔴 重启后激活', '🔴 未生效'],
        setup: st.setup === 'failed' ? ['❌ 首次下载失败', '❌ 下载失败'] : ['⏳ 首个列表尚未下载', '⏳ 等待初始化']
      };
      alert.classList.toggle('is-info', mode === 'setup');
      $('ribbon-long').textContent = texts[mode][0];
      $('ribbon-short').textContent = texts[mode][1];
      $('ribbon-btn').textContent = mode === 'setup' ? '⬇️ 立即下载' : '🔁 立即重启';
      $('ribbon-btn').className = 'btn btn-xs ' + (mode === 'setup' ? 'btn-primary' : 'btn-warn');
      $('ribbon-btn').setAttribute('data-mode', mode);
      $('ribbon-btn').disabled = S.busy && mode === 'setup';
      alert.hidden = false;
      nav.hidden = true;
    } else {
      alert.hidden = true;
      nav.hidden = false;
    }

    const count = $('hero-count');
    clear(count);
    const sub = $('hero-sub');
    if (st.setup !== 'ready') {
      count.appendChild(h('span', { class: 'num is-muted', text: '—' }));
      sub.textContent = st.setup === 'failed' ? '首次下载失败，点击“立即下载”重试' : '正在等待首次下载';
    } else if (!st.enabled) {
      count.appendChild(h('span', { class: 'num is-muted', text: '已暂停' }));
      sub.textContent = st.reboot ? '重启后将停止拦截' : '拦截已关闭';
    } else {
      count.appendChild(h('span', { class: 'num', text: fmtNum(st.domains) }));
      if (st.reboot) sub.textContent = '域名已就绪，重启后生效';
      else if (st.applied === 'overridden') sub.textContent = '域名已就绪，但被其他模块覆盖';
      else if (st.applied === 'inactive') sub.textContent = '域名已就绪，重启后激活';
      else sub.textContent = '已全系统拦截域名';
    }

    const addons = st.addons || [];
    const hl = clear($('hero-list'));
    hl.appendChild(h('span', { class: 'hl-name', text: '📋 ' + (st.listName || 'StevenBlack Main') }));
    hl.appendChild(h('span', { class: 'lvl lvl-' + (st.level || 'green'), text: (LEVEL[st.level] || '🟢') + ' ' + (st.levelText || '') }));
    if (addons.length) hl.appendChild(h('span', { class: 'hl-more', text: '➕ ' + addons.length + ' ' + plural(addons.length, '个附加列表', '个附加列表') }));
    $('stat-rules').textContent = '✅ ' + fmtNum(st.allow) + '  ·  ⛔ ' + fmtNum(st.block);
    const upd = $('stat-updated');
    upd.textContent = st.setup === 'ready' ? ago(st.updated) : '尚未更新';
    upd.classList.toggle('is-stale', isStale(st));
    const ap = appliedText(st.applied);
    const apEl = $('hero-applied');
    apEl.textContent = ap[0];
    apEl.className = 'hero-applied ' + ap[1];

    const tags = clear($('hero-tags'));
    tags.appendChild(h('span', { class: 'fact', text: st.live ? '⚡ 即时生效' : '🔁 重启后生效' }));
    tags.appendChild(h('span', { class: 'fact', text: '🔄 自动更新：' + (AUTO_TEXT[st.autoupdate] || '关闭') }));
    if (st.guard) tags.appendChild(h('span', { class: 'fact', text: '🔏 私人 DNS 已保护' }));

    renderPowerSwitch(st);
    let actNote = '🔄 仅当源列表发生变化时才会下载更新。';
    if (!st.enabled) actNote = '🔴 拦截已关闭。开启后才能切换或更新列表。';
    else if (isStale(st)) actNote = '🕒 你的列表已经 ' + staleDaysOf(st) + ' 天未更新。请点击“更新列表”，或在设置中开启自动更新。';
    $('actions-note').textContent = actNote;
    $('lists-note').textContent = st.enabled
      ? '选择一份拦截列表。越严格的列表拦截越多，也越可能影响正常使用。'
      : '🔴 拦截已关闭。请先在 🛡️ 防护 中打开开关，再切换或更新列表。';
    applyBusy();
  }

  const cards = {};
  const rows = {};

  function makeCard(id) {
    const c = {};
    c.name = h('h3', { class: 'lc-name' });
    c.lvl = h('span', { class: 'lvl' });
    c.desc = h('p', { class: 'lc-desc' });
    c.count = h('span');
    c.date = h('span');
    c.retry = h('button', { class: 'btn btn-ghost btn-xs invisible', type: 'button', text: '🔁 重试' });
    c.use = h('button', { class: 'btn btn-primary btn-xs', type: 'button', text: '⬇️ 使用此列表' });
    c.active = h('span', { class: 'lc-active', text: '✅ 当前使用' });
    c.retry.addEventListener('click', () => refreshMeta(id));
    c.use.addEventListener('click', () => confirmApply(id));
    c.card = h('article', { class: 'lcard' },
      h('div', { class: 'lc-top' }, c.name, c.lvl),
      c.desc,
      h('div', { class: 'lc-meta' }, c.count, c.date),
      h('div', { class: 'lc-foot' }, c.retry, h('span', null, c.use, c.active))
    );
    return c;
  }

  function renderLists() {
    const L = S.lists;
    if (!L || !L.lists) return;
    const groups = { unified: $('group-unified'), hagezi: $('group-hagezi') };
    const fresh = {};
    L.lists.forEach((l) => {
      let c = cards[l.id];
      if (!c) {
        c = cards[l.id] = makeCard(l.id);
        fresh[l.group] = true;
      }
      updateCard(c, l);
    });
    Object.keys(fresh).forEach((g) => {
      const box = groups[g];
      if (!box) return;
      clear(box);
      L.lists.forEach((l) => { if (l.group === g) box.appendChild(cards[l.id].card); });
    });
    renderAddons();
  }

  function updateCard(c, l) {
    const L = S.lists;
    const st = S.status;
    c.name.textContent = l.name;
    c.lvl.className = 'lvl lvl-' + l.level;
    c.lvl.textContent = (LEVEL[l.level] || '') + ' ' + l.levelText;
    c.desc.textContent = l.desc;
    c.desc.title = l.desc;
    clear(c.count);
    clear(c.date);
    c.count.className = '';
    const hasCount = l.count !== null && l.count !== undefined;
    if (hasCount) {
      c.count.textContent = '🔢 ' + fmtNum(l.count) + ' 条';
      c.date.textContent = '📅 ' + (l.date ? fmtDate(l.date) : '未知');
    } else if (l.busy || !l.error) {
      c.count.appendChild(sk('sk-line'));
      c.date.appendChild(sk('sk-line'));
    } else {
      c.count.textContent = '❌ 无法获取条目数量';
      c.count.className = 'is-err';
      c.date.textContent = '📅 ' + (l.date ? fmtDate(l.date) : '未知');
    }
    c.retry.classList.toggle('invisible', !(l.error && !l.busy));
    c.retry.disabled = !!l.busy;
    const isActive = !!(L && L.active === l.id && (!st || st.setup === 'ready'));
    c.card.classList.toggle('is-active', isActive);
    c.use.hidden = isActive;
    c.active.hidden = !isActive;
    const enabled = st ? st.enabled : (L ? L.enabled : true);
    c.use.disabled = S.busy || S.syncBusy || !enabled;
    c.use.title = !enabled ? '请先开启拦截' : '';
  }

  function activeAddonIds() {
    if (!S.lists || !S.lists.addons) return [];
    return S.lists.addons.filter((a) => a.enabled).map((a) => a.id);
  }

  function addonSelection() {
    return S.addonSel ? S.addonSel : activeAddonIds();
  }

  function sameIds(a, b) {
    if (a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) if (b.indexOf(a[i]) < 0) return false;
    return true;
  }

  function addonDiff() {
    const active = activeAddonIds();
    const sel = addonSelection();
    return {
      on: sel.filter((id) => active.indexOf(id) < 0),
      off: active.filter((id) => sel.indexOf(id) < 0)
    };
  }

  function addonsLocked() {
    const st = S.status;
    return S.busy || S.syncBusy || !st || !st.enabled || st.setup !== 'ready';
  }

  function makeRow(id) {
    const r = {};
    r.ico = h('span', { class: 'arow-ico', 'aria-hidden': 'true' });
    r.name = h('span', { class: 'arow-name' });
    r.top = h('div', { class: 'arow-top' }, r.name);
    r.desc = h('div', { class: 'arow-desc' });
    r.meta = h('div', { class: 'arow-meta' });
    r.sw = h('button', { class: 'switch', type: 'button', role: 'switch', 'aria-checked': 'false' });
    r.del = h('button', { class: 'rule-x', type: 'button', text: '🗑️', hidden: true });
    r.sw.addEventListener('click', () => toggleAddon(id));
    r.del.addEventListener('click', () => removeCustom(id));
    r.row = h('div', { class: 'arow' }, r.ico, h('div', { class: 'arow-text' }, r.top, r.desc, r.meta), h('div', { class: 'arow-side' }, r.del, r.sw));
    return r;
  }

  function updateRow(r, a) {
    const sel = addonSelection();
    const on = sel.indexOf(a.id) >= 0;
    r.ico.textContent = a.icon || '🧩';
    r.name.textContent = a.name;
    while (r.top.children.length > 1) r.top.removeChild(r.top.lastChild);
    if (a.suggested) r.top.appendChild(h('span', { class: 'tag tag-good', text: '✨ 适合你的设备' }));
    if (a.warn === 'heavy') r.top.appendChild(h('span', { class: 'tag tag-warn', text: '🐘 大体积' }));
    if (a.warn === 'breaks') r.top.appendChild(h('span', { class: 'tag tag-warn', text: '⚠️ 严格' }));
    r.desc.textContent = a.desc;
    r.desc.title = a.desc;
    clear(r.meta);
    r.meta.className = 'arow-meta';
    const known = a.count !== null && a.count !== undefined ? a.count : a.installed;
    if (known !== null && known !== undefined) {
      let m = '🔢 ' + fmtNum(known) + ' ' + plural(known, '条', '条');
      if (a.enabled && a.added !== null && a.added !== undefined) m += '  ·  ➕ 新增 ' + fmtNum(a.added);
      r.meta.textContent = m;
    } else if (a.error && !a.busy) {
      r.meta.textContent = '❌ 无法获取详情';
      r.meta.className = 'arow-meta is-err';
    } else if (a.custom && !a.busy) {
      r.meta.textContent = a.enabled ? '🔢 已安装' : '🔢 首次下载后显示大小';
    } else {
      r.meta.appendChild(sk('sk-line w-40'));
    }
    r.row.classList.toggle('is-on', on);
    r.row.classList.toggle('is-changed', on !== !!a.enabled);
    r.sw.setAttribute('aria-checked', on ? 'true' : 'false');
    r.sw.setAttribute('aria-label', (on ? '关闭 ' : '开启 ') + a.name);
    r.sw.disabled = addonsLocked();
    r.del.hidden = !a.custom;
    r.del.disabled = S.busy || S.syncBusy;
    r.del.setAttribute('aria-label', '移除 ' + a.name);
  }

  function renderAddons() {
    const L = S.lists;
    if (!L || !L.addons) return;
    const box = $('addons');
    const ids = L.addons.map((a) => a.id);
    if (S.addonSel) {
      const kept = S.addonSel.filter((id) => ids.indexOf(id) >= 0);
      S.addonSel = sameIds(kept, activeAddonIds()) ? null : kept;
    }
    Object.keys(rows).forEach((id) => { if (ids.indexOf(id) < 0) delete rows[id]; });
    const sig = ids.join(',');
    if (box.getAttribute('data-sig') !== sig) {
      clear(box);
      ADDON_GROUPS.forEach((g) => {
        const items = L.addons.filter((a) => a.group === g[0]);
        if (!items.length && g[0] !== 'custom') return;
        const head = h('div', { class: 'agroup' }, h('span', { text: g[1] }));
        if (g[0] === 'custom') {
          const add = h('button', { class: 'btn btn-ghost btn-xs', type: 'button', id: 'custom-add', text: '➕ 添加列表' });
          add.addEventListener('click', addCustomFlow);
          head.appendChild(add);
        }
        box.appendChild(head);
        if (!items.length) box.appendChild(h('div', { class: 'empty', text: '🌱 通过地址添加任意 HTTPS hosts 或域名列表。' }));
        items.forEach((a) => {
          if (!rows[a.id]) rows[a.id] = makeRow(a.id);
          box.appendChild(rows[a.id].row);
        });
      });
      box.setAttribute('data-sig', sig);
    }
    L.addons.forEach((a) => { if (rows[a.id]) updateRow(rows[a.id], a); });
    const add = $('custom-add');
    if (add) add.disabled = S.busy || S.syncBusy || L.addons.filter((a) => a.custom).length >= (L.customMax || 8);
    renderAddonBar();
  }

  function renderAddonBar() {
    const d = addonDiff();
    const n = d.on.length + d.off.length;
    const bar = $('addon-bar');
    bar.hidden = n === 0;
    $('addon-bar-text').textContent = '🧩 ' + n + ' ' + plural(n, '项更改', '项更改');
    $('addon-apply').disabled = addonsLocked();
    $('addon-reset').disabled = S.busy || S.syncBusy;
  }

  function toggleAddon(id) {
    if (addonsLocked()) {
      const st = S.status;
      if (st && !st.enabled) toast('🔴 请先开启拦截。', 'warn');
      else if (st && st.setup !== 'ready') toast('⏳ 请先下载主列表。', 'warn');
      return;
    }
    const sel = addonSelection().slice();
    const i = sel.indexOf(id);
    if (i >= 0) sel.splice(i, 1);
    else sel.push(id);
    S.addonSel = sameIds(sel, activeAddonIds()) ? null : sel;
    renderAddons();
  }

  function resetAddons() {
    S.addonSel = null;
    renderAddons();
  }

  function renderRules() {
    const R = S.rules;
    $('count-allow').textContent = String(R.allow.length);
    $('count-block').textContent = String(R.block.length);
    const ta = $('tab-allow');
    const tb = $('tab-block');
    ta.classList.toggle('is-on', S.tab === 'allow');
    tb.classList.toggle('is-on', S.tab === 'block');
    ta.setAttribute('aria-selected', S.tab === 'allow' ? 'true' : 'false');
    tb.setAttribute('aria-selected', S.tab === 'block' ? 'true' : 'false');
    const ul = clear($('rule-list'));
    const all = R[S.tab] || [];
    const wrap = $('rule-filter-wrap');
    wrap.hidden = all.length <= 8 && !S.ruleFilter;
    const q = S.ruleFilter.trim().toLowerCase();
    const list = q ? all.filter((d) => d.indexOf(q) >= 0) : all;
    if (!all.length) {
      ul.appendChild(h('li', { class: 'empty', text: S.tab === 'allow' ? '🌱 还没有放行规则。在上方添加域名，即可始终放行。' : '🌱 还没有拦截规则。在上方添加域名，即可始终拦截。' }));
      return;
    }
    if (!list.length) {
      ul.appendChild(h('li', { class: 'empty', text: '🔎 没有匹配“' + q + '”的规则。' }));
      return;
    }
    const type = S.tab;
    const frag = document.createDocumentFragment();
    list.slice().reverse().forEach((d) => {
      const x = h('button', { class: 'rule-x', type: 'button', 'aria-label': '移除 ' + d, text: '🗑️' });
      x.disabled = S.busy || S.syncBusy;
      x.addEventListener('click', () => deleteRule(type, d, x));
      frag.appendChild(h('li', { class: 'rule' }, h('span', { class: 'rule-d', text: (type === 'allow' ? '✅ ' : '⛔ ') + d }), x));
    });
    ul.appendChild(frag);
  }

  function visibleLogs() {
    const logs = S.logs || [];
    if (S.logLevel === 'error') return logs.filter((l) => l.l === 'ERROR');
    if (S.logLevel === 'warn') return logs.filter((l) => l.l === 'ERROR' || l.l === 'WARN');
    return logs;
  }

  function renderLogs() {
    const box = $('logbox');
    const logs = visibleLogs();
    const last = logs.length ? logs[logs.length - 1] : null;
    const sig = S.logLevel + '|' + logs.length + '|' + (last ? last.t + last.m : '');
    if (sig === S.logSig) return;
    const first = S.logSig === '' || S.logSig.split('|')[0] !== S.logLevel;
    S.logSig = sig;
    const nearBottom = box.scrollHeight - box.scrollTop - box.clientHeight < 48;
    clear(box);
    if (!logs.length) {
      const empty = { all: '📭 暂无日志。', warn: '✅ 没有警告或错误。', error: '✅ 没有错误。' };
      box.appendChild(h('div', { class: 'empty', text: empty[S.logLevel] || empty.all }));
      return;
    }
    const frag = document.createDocumentFragment();
    logs.forEach((l) => {
      const lvl = l.l === 'ERROR' ? ['is-error', '❌ 错误'] : (l.l === 'WARN' ? ['is-warn', '⚠️ 警告'] : ['is-info', 'ℹ️ 信息']);
      frag.appendChild(h('div', { class: 'log ' + lvl[0] },
        h('span', { class: 'log-t', text: logTime(l.t) }),
        h('span', { class: 'log-l', text: lvl[1] }),
        h('span', { class: 'log-m', text: l.m })
      ));
    });
    box.appendChild(frag);
    if (first || nearBottom) box.scrollTop = box.scrollHeight;
  }

  function setLogLevel(level) {
    S.logLevel = level;
    const fs = document.querySelectorAll('.filter');
    for (let i = 0; i < fs.length; i++) {
      const on = fs[i].getAttribute('data-level') === level;
      fs[i].classList.toggle('is-on', on);
      fs[i].setAttribute('aria-selected', on ? 'true' : 'false');
    }
    renderLogs();
  }

  function applyBusy() {
    const st = S.status;
    const busy = S.busy || S.syncBusy;
    const enabled = st ? !!st.enabled : true;
    $('act-update').disabled = busy || !enabled || !st;
    $('act-toggle').disabled = busy || !st;
    $('act-repair').disabled = busy || !st;
    $('act-settings').disabled = !st;
    $('rule-allow').disabled = busy;
    $('rule-block').disabled = busy;
    $('rules-import').disabled = busy;
    $('logs-clear').disabled = false;
    Object.keys(cards).forEach((id) => {
      cards[id].use.disabled = busy || !enabled;
    });
    Object.keys(rows).forEach((id) => {
      rows[id].sw.disabled = addonsLocked();
      rows[id].del.disabled = busy;
    });
    const add = $('custom-add');
    if (add && busy) add.disabled = true;
    renderAddonBar();
    const xs = document.querySelectorAll('#rule-list .rule-x');
    for (let i = 0; i < xs.length; i++) xs[i].disabled = busy;
    const lk = document.querySelectorAll('#lookup .btn');
    for (let i = 0; i < lk.length; i++) lk[i].disabled = busy;
    if (st) {
      const rb = $('ribbon-btn');
      if (rb.getAttribute('data-mode') === 'setup') rb.disabled = busy;
    }
  }

  const PV = { built: false };

  function buildProgress() {
    PV.steps = STEPS.map((s) => h('div', { class: 'step' }, h('span', { class: 'step-e', text: s[1] }), h('span', { text: s[2] })));
    PV.phase = h('span');
    PV.pct = h('span', { class: 'pg-pct' });
    PV.fill = h('div', { class: 'bar-fill' });
    PV.bar = h('div', { class: 'bar is-indet' }, PV.fill, h('div', { class: 'bar-stripes' }));
    PV.left = h('span');
    PV.right = h('span');
    PV.root = h('div', { class: 'prog' },
      h('div', { class: 'steps' }, PV.steps),
      h('div', { class: 'pg-phase' }, PV.phase, PV.pct),
      PV.bar,
      h('div', { class: 'pg-meta' }, PV.left, PV.right)
    );
    PV.built = true;
  }

  function opTitle(op) {
    const name = listName(op.list);
    if (op.kind === 'update' || op.kind === 'auto') return '正在更新列表';
    if (op.kind === 'enable') return '正在重新开启拦截';
    if (op.kind === 'addons') return '正在应用附加列表';
    if (op.kind === 'setup') return '正在下载 ' + name;
    return '正在安装 ' + name;
  }

  function opIcon(op) {
    if (op.kind === 'update' || op.kind === 'auto') return '🔄';
    if (op.kind === 'addons') return '🧩';
    return '⬇️';
  }

  function showProgress(op) {
    if (Modal.view() !== 'progress' || !Modal.open()) {
      buildProgress();
      Modal.show({
        icon: opIcon(op),
        title: opTitle(op),
        body: [PV.root],
        view: 'progress',
        onDismiss: hideProgress,
        actions: [
          { label: '✖️ 取消', class: 'btn-ghost', id: 'pg-cancel', onClick: cancelOp },
          { label: '🔽 收起', class: 'btn-ghost', onClick: hideProgress }
        ]
      });
    }
    hideMini();
    updateProgress(op);
  }

  function trackSpeed(op) {
    const sp = S.speed;
    const now = performance.now();
    if (!op.running || op.phase !== 'download') {
      sp.t = 0;
      sp.b = 0;
      return sp.v;
    }
    if (!sp.t || op.bytes < sp.b) {
      sp.t = now;
      sp.b = op.bytes;
      sp.v = 0;
      return 0;
    }
    if (now - sp.t >= 300) {
      const inst = (op.bytes - sp.b) / ((now - sp.t) / 1000);
      sp.v = sp.v ? sp.v * 0.6 + inst * 0.4 : inst;
      sp.t = now;
      sp.b = op.bytes;
    }
    return sp.v;
  }

  function progressNumbers(op) {
    const order = { prepare: -1, check: -1, download: 0, verify: 1, optimize: 2, install: 3, finish: 4 };
    const idx = order[op.phase] === undefined ? -1 : order[op.phase];
    const total = Number(op.total) || 0;
    const bytes = Number(op.bytes) || 0;
    let ratio = -1;
    if (op.phase === 'download' && total > 0) ratio = Math.min(1, bytes / total);
    return { idx: idx, total: total, bytes: bytes, ratio: ratio };
  }

  function phaseLine(op) {
    if (op.cancelling) return '✖️ 正在取消…';
    const base = PHASE_TEXT[op.phase] || PHASE_TEXT.prepare;
    const fetching = op.phase === 'check' || op.phase === 'download' || op.phase === 'verify' || op.phase === 'optimize';
    if (!fetching || !op.sourceName) return base;
    const verb = { check: '🔎 正在检查', download: '⬇️ 正在下载', verify: '🔍 正在校验', optimize: '🧹 正在优化' }[op.phase];
    let line = verb + ' ' + op.sourceName;
    if (op.items > 1 && op.item > 0) line += '（第 ' + op.item + ' 个，共 ' + op.items + ' 个）';
    return line + '…';
  }

  function updateProgress(op) {
    if (!PV.built) return;
    const n = progressNumbers(op);
    const speed = trackSpeed(op);
    PV.steps.forEach((el, i) => {
      el.classList.toggle('is-done', i < n.idx);
      el.classList.toggle('is-active', i === n.idx);
    });
    PV.phase.textContent = phaseLine(op);
    if (n.ratio >= 0) {
      PV.bar.classList.remove('is-indet');
      PV.fill.style.transform = 'scaleX(' + n.ratio.toFixed(4) + ')';
      PV.pct.textContent = Math.floor(n.ratio * 100) + '%';
    } else {
      PV.bar.classList.add('is-indet');
      PV.fill.style.transform = 'scaleX(' + (n.idx > 0 ? 1 : 0) + ')';
      PV.pct.textContent = '';
    }
    if (op.phase === 'download') {
      PV.left.textContent = n.total > 0 ? fmtMB(n.bytes) + ' / ' + fmtMB(n.total) : '已下载 ' + fmtMB(n.bytes);
      PV.right.textContent = speed > 0 ? fmtMB(speed) + '/s' : '';
    } else if (n.idx > 0) {
      PV.left.textContent = n.total > 0 ? '✅ 已下载 ' + fmtMB(n.total) : '✅ 下载完成';
      PV.right.textContent = '';
    } else {
      PV.left.textContent = op.phase === 'check' ? '正在与源列表比对…' : '正在准备…';
      PV.right.textContent = '';
    }
    const cancel = $('pg-cancel');
    if (cancel) {
      cancel.disabled = !op.cancellable || !!op.cancelling;
      const lab = cancel.querySelector('.btn-label') || cancel;
      lab.textContent = op.cancelling ? '✖️ 正在取消…' : '✖️ 取消';
    }
    updateMini(op);
  }

  function hideProgress() {
    S.opView = false;
    if (Modal.view() === 'progress') Modal.close();
    if (S.op && S.op.running) showMini(S.op);
  }

  function showMini(op) {
    const m = $('mini');
    m.hidden = false;
    document.body.classList.add('has-mini');
    updateMini(op);
  }

  function hideMini() {
    $('mini').hidden = true;
    document.body.classList.remove('has-mini');
  }

  function updateMini(op) {
    const m = $('mini');
    if (m.hidden) return;
    const n = progressNumbers(op);
    let text = phaseLine(op).replace('…', '');
    if (!op.sourceName) text += ' • ' + listName(op.list);
    if (n.ratio >= 0) text += ' • ' + Math.floor(n.ratio * 100) + '%';
    $('mini-text').textContent = text;
    const r = n.ratio >= 0 ? n.ratio : (n.idx >= 0 ? (n.idx + 1) / 5 : 0.05);
    $('mini-fill').style.transform = 'scaleX(' + r.toFixed(4) + ')';
  }

  let pollTimer = 0;
  let polling = false;

  function schedulePoll(ms) {
    clearTimeout(pollTimer);
    pollTimer = setTimeout(pollOp, ms);
  }

  async function pollOp() {
    if (polling) return;
    polling = true;
    const r = await api('progress');
    polling = false;
    if (r.ok) handleOp(r.data);
    if (S.op && S.op.running) schedulePoll(document.hidden ? 2000 : 400);
  }

  function markSeen(seq) {
    if (seq > S.seen) {
      S.seen = seq;
      store.set('hostkeeper-seq', String(seq));
    }
  }

  function handleOp(op) {
    if (!op || typeof op !== 'object') return;
    const wasBusy = S.busy;
    S.op = op;
    if (op.running) {
      S.busy = true;
      if (!wasBusy && !S.opView && Modal.view() !== 'progress' && !Modal.open() && op.kind !== 'auto') S.opView = true;
      if (S.opView) showProgress(op);
      else {
        if (Modal.view() !== 'progress') showMini(op);
        updateMini(op);
      }
      applyBusy();
      if (!pollTimer || !wasBusy) schedulePoll(400);
      return;
    }
    S.busy = false;
    S.speed = { t: 0, b: 0, v: 0 };
    hideMini();
    applyBusy();
    const finished = op.seq && op.seq > S.seen && op.state && op.state !== 'idle';
    if (!finished) {
      if (Modal.view() === 'progress') Modal.close();
      S.opView = false;
      return;
    }
    const recent = wasBusy || (op.ended && nowSec() - op.ended < 600);
    markSeen(op.seq);
    if (!recent) return;
    S.addonSel = null;
    if (S.opView || Modal.view() === 'progress') showResult(op);
    else if (op.kind !== 'auto' || op.code !== 'up_to_date') toast(op.message, op.state === 'success' ? 'ok' : (op.state === 'cancelled' ? 'info' : 'err'));
    S.opView = false;
    refreshAll();
  }

  function showResult(op) {
    const msg = stripLead(op.message);
    let icon = '✅';
    let title = '已完成';
    let actions = gotIt();
    const body = [para(msg, 'center')];
    if (op.state === 'success') {
      if (op.code === 'up_to_date') title = '已是最新版本';
      else if (op.code === 'unchanged') title = '没有需要更改的内容';
      else if (op.kind === 'update' || op.kind === 'auto') title = '列表已更新';
      else if (op.kind === 'addons') title = '附加列表已应用';
      else title = '已准备就绪';
      if (op.reboot) {
        body.push(note('💡 不用着急，重启前当前防护仍然有效。', 'warn'));
        actions = [
          { label: '⏰ 稍后', class: 'btn-ghost', onClick: () => Modal.close() },
          { label: '🔁 立即重启', class: 'btn-warn', onClick: rebootFlow }
        ];
      } else if (op.live) {
        body.push(note('⚡ 已即时生效。已经打开的应用可能需要重启才能感知。'));
      }
    } else if (op.state === 'cancelled') {
      icon = '✖️';
      title = '已取消';
    } else {
      icon = '❌';
      const t = { apply: '无法切换列表', update: '更新失败', auto: '更新失败', enable: '无法开启拦截', setup: '下载失败', addons: '无法应用附加列表' };
      title = t[op.kind] || '出现了一些问题';
      if (!/没有更改|已恢复|未受影响|保持原样|原文件/i.test(op.message || '')) body.push(note('🛟 没有丢失数据，之前的 hosts 文件仍然保留。', 'err'));
      if (op.kind === 'apply' || op.kind === 'update' || op.kind === 'setup' || op.kind === 'enable') {
        actions = [
          { label: '👌 知道了', class: 'btn-ghost', onClick: () => Modal.close() },
          { label: '🔁 重试', class: 'btn-primary', onClick: () => retryOp(op) }
        ];
      }
    }
    Modal.show({ icon: icon, title: title, body: body, actions: actions, view: 'result' });
  }

  function retryOp(op) {
    if (op.kind === 'update' || op.kind === 'setup') return runUpdate();
    if (op.kind === 'enable') return toggleBlocker();
    return startApply(op.list);
  }

  function showReplyError(r, kind) {
    S.opView = false;
    const t = { apply: '无法切换列表', update: '无法开始更新', enable: '无法开启拦截', addons: '无法应用附加列表', source: '无法添加列表' };
    if (r.code === 'offline' || r.code === 'unauthorized' || r.code === 'no_token' || r.code === 'framed') {
      Modal.close();
      return;
    }
    Modal.show({
      icon: r.code === 'busy' ? '⏳' : (r.code === 'already_active' ? '⚠️' : '❌'),
      title: r.code === 'busy' ? '请稍候' : (r.code === 'already_active' ? '已在生效中' : (t[kind] || '出现了一些问题')),
      body: [para(stripLead(r.message), 'center')],
      view: 'result',
      actions: gotIt()
    });
  }

  function resetSpeed() {
    S.speed = { t: 0, b: 0, v: 0 };
  }

  async function confirmApply(id) {
    const l = findList(id);
    const st = S.status;
    if (!l || !st || S.busy) return;
    if (!st.enabled) {
      toast('🔴 请先开启拦截。', 'warn');
      return;
    }
    const facts = [];
    if (l.count) facts.push(h('span', { class: 'fact', text: '🔢 ~' + fmtNum(l.count) + ' 条' }));
    if (l.size) facts.push(h('span', { class: 'fact', text: '⬇️ ~' + fmtMB(l.size) }));
    if (l.date) facts.push(h('span', { class: 'fact', text: '📅 ' + fmtDate(l.date) }));
    const body = [
      h('div', { class: 'facts facts-top' }, h('span', { class: 'lvl lvl-' + l.level, text: (LEVEL[l.level] || '') + ' ' + l.levelText })),
      para(l.desc, 'center')
    ];
    if (facts.length) body.push(h('div', { class: 'facts' }, facts));
    if (l.level === 'orange' || l.level === 'red') {
      body.push(note('⚠️ 这是一份严格列表，部分网站或应用功能可能无法使用；你随时可以在 🧩 域名规则 中放行域名。', 'warn'));
    }
    const kept = (st.addons || []).length;
    body.push(note((st.live ? '⚡ 设备允许时会立即生效。' : '🔁 需要重启后才能生效。') + ' 你的域名规则' + (kept ? '和附加列表' : '') + '会保留。'));
    const ok = await confirmBox({ icon: '📋', title: '切换到 ' + l.name + '？', body: body, ok: '⬇️ 应用列表' });
    if (!ok) return;
    startApply(id);
  }

  async function startJob(kind, cmd, args, first) {
    S.opView = true;
    resetSpeed();
    showProgress(Object.assign({ running: true, kind: kind, phase: 'prepare', bytes: 0, total: 0, cancellable: false }, first || {}));
    const r = await api(cmd, args);
    if (!r.ok || r.code !== 'started') {
      if (r.ok) {
        S.opView = false;
        Modal.close();
        toast(r.message, 'ok');
        refreshAll();
      } else {
        showReplyError(r, kind);
      }
      return r;
    }
    handleOp(r.data.op);
    schedulePoll(400);
    return r;
  }

  function startApply(id) {
    return startJob('apply', 'apply', [id], { list: id });
  }

  function runUpdate() {
    const st = S.status;
    if (!st || !st.enabled || S.busy) return null;
    const ready = st.setup === 'ready';
    return startJob(ready ? 'update' : 'setup', 'update', [], { list: st.list, phase: ready ? 'check' : 'prepare' });
  }

  async function applyAddons() {
    if (addonsLocked()) return;
    const d = addonDiff();
    if (!d.on.length && !d.off.length) return;
    const items = [];
    let extra = 0;
    const warns = [];
    d.on.forEach((id) => {
      const a = findAddon(id);
      if (!a) return;
      items.push(h('li', { text: '➕ ' + (a.icon ? a.icon + ' ' : '') + a.name + (a.count ? ' · 约 ' + fmtNum(a.count) + ' 条' : '') }));
      extra += Number(a.count) || 0;
      if (a.warn && ADDON_WARN[a.warn] && warns.indexOf(ADDON_WARN[a.warn]) < 0) warns.push(ADDON_WARN[a.warn]);
    });
    d.off.forEach((id) => {
      const a = findAddon(id);
      if (a) items.push(h('li', { text: '➖ ' + (a.icon ? a.icon + ' ' : '') + a.name }));
    });
    const body = [h('ul', { class: 'change-list' }, items)];
    warns.forEach((w) => body.push(note(w, 'warn')));
    if (extra > 0) body.push(note('🧮 最多增加 ' + fmtNum(extra) + ' 条记录；列表已拦截的域名只计算一次。'));
    const ok = await confirmBox({ icon: '🧩', title: '应用附加列表变更？', body: body, ok: '✅ 应用' });
    if (!ok) return;
    const sel = addonSelection().slice();
    await startJob('addons', 'addons', [sel.join(',')], { list: S.status ? S.status.list : '' });
  }

  function checkUrl(raw) {
    const s = String(raw || '').trim();
    if (!s) return { err: '✏️ 请先输入列表地址。' };
    if (!/^https:\/\//i.test(s)) return { err: '🚫 请输入完整的 HTTPS 地址，例如 https://example.com/hosts.txt' };
    if (s.length > 300) return { err: '🚫 该地址过长。' };
    if (/[^A-Za-z0-9._~:/?&=%+,@-]/.test(s)) return { err: '🚫 该地址包含不允许的字符。' };
    // Match the backend rule: userinfo in the authority is never accepted.
    if (/^https:\/\/[^/?#]*@/i.test(s)) return { err: '🚫 不允许包含用户名的地址。' };
    return { url: 'https://' + s.slice(8) };
  }

  function addCustomFlow() {
    if (S.busy || S.syncBusy) return;
    const url = h('input', { type: 'text', inputmode: 'url', autocomplete: 'off', autocapitalize: 'off', autocorrect: 'off', spellcheck: 'false', maxlength: '300', placeholder: 'https://example.com/hosts.txt', 'aria-label': '列表地址' });
    const name = h('input', { type: 'text', autocomplete: 'off', maxlength: '40', placeholder: '名称（可选）', 'aria-label': '列表名称' });
    const msg = h('p', { class: 'fine', text: '支持 hosts 文件、纯域名列表和简单的 ||domain^ 列表。' });
    const submit = async () => {
      const c = checkUrl(url.value);
      if (c.err) {
        msg.textContent = c.err;
        msg.className = 'fine is-err';
        return;
      }
      await startJob('source', 'source-add', [c.url, name.value.trim()], { kind: 'addons', list: S.status ? S.status.list : '' });
    };
    url.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); name.focus(); } });
    name.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); submit(); } });
    Modal.show({
      icon: '🔗',
      title: '添加自定义列表',
      body: [
        h('label', { class: 'field' }, url),
        h('label', { class: 'field' }, name),
        msg,
        note('🛡️ 无论列表内容是什么，HostKeeper 只会把条目转换为拦截规则，无法把域名重定向到其他地址。')
      ],
      view: 'custom',
      actions: [
        { label: '↩️ 暂不', class: 'btn-ghost', onClick: () => Modal.close() },
        { label: '➕ 添加列表', class: 'btn-primary', onClick: submit }
      ]
    });
    setTimeout(() => {
      try {
        url.focus({ preventScroll: true });
      } catch (e) {
        url.focus();
      }
    }, 280);
  }

  async function removeCustom(id) {
    const a = findAddon(id);
    if (!a || S.busy || S.syncBusy) return;
    const ok = await confirmBox({
      icon: '🗑️',
      title: '移除 ' + a.name + '?',
      body: [para('该列表将从 HostKeeper 中移除' + (a.enabled ? '，其条目也会停止拦截。' : '。'), 'center')],
      ok: '🗑️ 移除',
      okClass: 'btn-danger'
    });
    if (!ok) return;
    Modal.close();
    setSyncBusy(true);
    const r = await api('source-del', [id]);
    setSyncBusy(false);
    toast(r.message, r.ok ? 'ok' : 'err');
    S.addonSel = null;
    refreshAll();
  }

  async function cancelOp() {
    const btn = $('pg-cancel');
    if (btn) btn.disabled = true;
    const r = await api('cancel');
    if (r.ok) {
      if (S.op) {
        S.op.cancelling = true;
        updateProgress(S.op);
      }
    } else {
      toast(r.message, 'warn');
      if (btn && S.op) btn.disabled = !S.op.cancellable;
    }
  }

  async function toggleBlocker() {
    const st = S.status;
    if (!st || S.busy || S.syncBusy) return;
    if (st.enabled) {
      const ok = await confirmBox({
        iconNode: powerIcon(),
        title: '关闭 HostKeeper？',
        body: [para('广告和追踪器将' + (st.live ? '从现在起不再被拦截' : '在下次重启后不再被拦截') + '。列表和域名规则会保留，你随时可以重新开启。', 'center')],
        ok: '关闭',
        okClass: 'btn-danger',
        power: true
      });
      if (!ok) return;
      Modal.close();
      setSyncBusy(true);
      const r = await api('disable');
      setSyncBusy(false);
      toast(r.message, r.ok ? 'warn' : 'err');
      refreshAll();
      return;
    }
    setSyncBusy(true);
    const r = await api('enable');
    setSyncBusy(false);
    if (r.ok && r.code === 'started') {
      S.opView = true;
      handleOp(r.data.op);
      schedulePoll(400);
    } else {
      toast(r.message, r.ok ? 'ok' : 'err');
    }
    refreshAll();
  }

  function setSyncBusy(v) {
    S.syncBusy = v;
    applyBusy();
  }

  async function rebootFlow() {
    const ok = await confirmBox({
      icon: '🔁',
      title: '立即重启？',
      body: [para('设备将重启以应用新的 hosts 文件。请先保存其他应用中的工作。', 'center')],
      ok: '🔁 重启',
      okClass: 'btn-warn'
    });
    if (!ok) return;
    const r = await api('reboot');
    if (r.ok) {
      Modal.show({ icon: '🔁', title: '正在重启…', body: [para('稍后见。重启后新设置即会生效。', 'center')], actions: [], dismissible: false, view: 'reboot' });
    } else {
      Modal.show({ icon: '❌', title: '无法重启', body: [para(stripLead(r.message), 'center')], view: 'result', actions: gotIt() });
    }
  }

  function statusRows(st) {
    const addons = st.addons || [];
    const mounts = { manager: 'Root 管理器', self: 'HostKeeper（直接挂载）', conflict: '其他模块', failed: '❌ 挂载失败' };
    return [
      ['🛡️ 拦截状态', st.enabled ? '🟢 开启' : '🔴 关闭'],
      ['📋 当前列表', st.listName || '—'],
      ['🎚️ 强度', (LEVEL[st.level] || '') + ' ' + (st.levelText || '')],
      ['➕ 附加列表', addons.length ? addons.map((a) => a.name).join('、') : '无'],
      ['🔢 已拦截域名', st.setup === 'ready' ? (st.enabled ? fmtNum(st.domains) : '0（已暂停）') : '—'],
      ['✅ 放行规则', fmtNum(st.allow) + (st.stats && st.stats.allowed ? ' · 正在放行 ' + fmtNum(st.stats.allowed) : '')],
      ['⛔ 拦截规则', fmtNum(st.block)],
      ['🕒 上次更新', st.updated && st.setup === 'ready' ? stampFmt.format(new Date(st.updated * 1000)) + ' · ' + ago(st.updated) : '从未'],
      ['🔄 自动更新', (AUTO_TEXT[st.autoupdate] || '关闭') + (st.autoupdate ? (st.sched ? ' · 运行中' : ' · 开机后启动') : '')],
      ['⚡ 即时生效', st.live ? '开启' : '关闭'],
      ['🔁 等待重启', st.reboot ? '🟡 是' : '否'],
      ['🧪 生效状态', appliedText(st.applied)[0]],
      ['🔗 挂载方', mounts[st.mount] || '—'],
      ['🔏 私人 DNS', st.guard ? st.guard + '（已保护）' : '未设置提供商主机名'],
      ['🧾 Hosts 文件', fmtMB(st.hostsSize)],
      ['🧰 Root 管理器', (st.manager || '未知') + (st.managerVersion ? ' ' + st.managerVersion : '')],
      ['📦 模块版本', (st.version || VERSION) + ' (' + (st.versionCode || VERSION_CODE) + ')'],
      ['🖥️ 界面', Bridge.mode === 'ksu' ? 'Root 管理器 WebUI' : '本地服务 · 127.0.0.1:9090']
    ];
  }

  async function showStatusDialog() {
    const btn = $('act-status');
    btn.disabled = true;
    const r = await api('status');
    btn.disabled = false;
    if (!r.ok) {
      toast(r.message, 'err');
      return;
    }
    S.status = r.data;
    renderStatus();
    const st = r.data;
    const list = h('div', { class: 'kv-list' }, statusRows(st).map((row) => h('div', { class: 'kv' }, h('span', { class: 'k', text: row[0] }), h('span', { class: 'v', text: row[1] }))));
    const body = [list];
    if (st.conflicts && st.conflicts.length) {
      const names = st.conflicts.map((c) => (c === 'hosts' ? '系统 hosts 模块' : c)).join(', ');
      body.push(note('⚠️ 以下模块也会替换 /system/etc/hosts：' + names + '。请停用它们，HostKeeper 才能正常工作。', 'warn'));
    }
    if (st.adaway) body.push(note('⚠️ 检测到 AdAway。请不要同时使用它的 root 或 systemless 模式与 HostKeeper。', 'warn'));
    if (st.applied === 'pending') body.push(note('🔁 最新更改已保存，将在重启后生效。'));
    if (st.applied === 'inactive') {
      body.push(note(st.mount === 'failed'
        ? '🔴 Android 未使用 HostKeeper 的 hosts 文件，且开机挂载失败。请查看 📜 日志 了解详情。'
        : '🔴 Android 尚未使用 HostKeeper 的 hosts 文件。请重启，HostKeeper 会在开机时自动挂载。', 'err'));
    }
    if (st.applied === 'applied' && st.mount === 'self') body.push(note('🔗 Root 管理器没有挂载 hosts 文件，因此 HostKeeper 直接进行了挂载。拦截工作正常。'));
    Modal.show({ icon: '📊', title: '状态', body: body, view: 'status', actions: gotIt() });
  }

  function switchRow(name, desc, on, onToggle) {
    const sw = h('button', { class: 'switch', type: 'button', role: 'switch', 'aria-checked': on ? 'true' : 'false', 'aria-label': name });
    sw.addEventListener('click', () => onToggle(sw));
    return h('div', { class: 'set-row' }, h('div', { class: 'set-text' }, h('div', { class: 'set-name', text: name }), h('div', { class: 'set-desc', text: desc })), sw);
  }

  async function saveSetting(key, value) {
    const r = await api('set', [key, String(value)]);
    toast(r.message, r.ok ? 'ok' : 'err');
    await loadStatus();
    return r;
  }

  function showSettings() {
    const st = S.status;
    if (!st) return;
    const live = switchRow('⚡ 即时生效', '把更改直接写入已挂载的 hosts 文件，无需重启即可生效。关闭后恢复经典方式：替换文件并重启。', !!st.live, async (sw) => {
      const next = sw.getAttribute('aria-checked') !== 'true';
      sw.disabled = true;
      const r = await saveSetting('live', next ? 1 : 0);
      sw.disabled = false;
      if (r.ok) sw.setAttribute('aria-checked', next ? 'true' : 'false');
    });
    const seg = h('div', { class: 'seg seg-4', role: 'tablist', 'aria-label': '自动更新间隔' });
    const paint = (v) => {
      for (let i = 0; i < seg.children.length; i++) {
        const on = Number(seg.children[i].getAttribute('data-v')) === Number(v);
        seg.children[i].classList.toggle('is-on', on);
        seg.children[i].setAttribute('aria-selected', on ? 'true' : 'false');
      }
    };
    AUTO_CHOICES.forEach((c) => {
      const b = h('button', { class: 'seg-btn', type: 'button', role: 'tab', 'data-v': String(c[0]), text: c[1] });
      b.addEventListener('click', async () => {
        for (let i = 0; i < seg.children.length; i++) seg.children[i].disabled = true;
        const r = await saveSetting('autoupdate', c[0]);
        for (let i = 0; i < seg.children.length; i++) seg.children[i].disabled = false;
        if (r.ok) paint(c[0]);
      });
      seg.appendChild(b);
    });
    paint(st.autoupdate || 0);
    const auto = h('div', { class: 'set-block' },
      h('div', { class: 'set-name', text: '🔄 自动更新' }),
      h('div', { class: 'set-desc', text: '按计划检查列表，只下载发生变化的内容。开启后会有一个轻量后台进程每 15 分钟醒来一次，判断是否该检查。' }),
      seg
    );
    Modal.show({
      icon: '⚙️',
      title: '设置',
      body: [live, auto, note('🌙 顶部的太阳/月亮按钮用于切换深色与浅色主题。')],
      view: 'settings',
      actions: gotIt()
    });
  }

  function diagIcon(level) {
    return { ok: '✅', warn: '⚠️', err: '❌', info: 'ℹ️' }[level] || 'ℹ️';
  }

  function diagView(d) {
    const sum = d.summary || { ok: 0, warn: 0, err: 0 };
    let line = '✅ 一切正常。';
    if (sum.err) line = '❌ ' + sum.err + ' 个问题需要处理。';
    else if (sum.warn) line = '⚠️ ' + sum.warn + ' 项值得注意。';
    const list = h('div', { class: 'diag-list' }, (d.checks || []).map((c) => h('div', { class: 'diag is-' + c.level },
      h('span', { class: 'diag-ico', text: diagIcon(c.level) }),
      h('div', { class: 'diag-body' }, h('div', { class: 'diag-t', text: c.title }), h('div', { class: 'diag-d', text: c.detail }))
    )));
    return [h('div', { class: 'diag-sum', text: line }), list];
  }

  async function showDiag() {
    const btn = $('act-diag');
    btn.disabled = true;
    Modal.show({ icon: '🩺', title: '健康检查', body: [para('正在检查 hosts 文件、挂载状态、列表和网络…', 'center')], view: 'diag', actions: [] });
    const r = await api('diag');
    btn.disabled = false;
    if (Modal.view() !== 'diag') return;
    if (!r.ok) {
      Modal.show({ icon: '❌', title: '健康检查失败', body: [para(stripLead(r.message), 'center')], view: 'result', actions: gotIt() });
      return;
    }
    Modal.show({
      icon: '🩺',
      title: '健康检查',
      body: diagView(r.data),
      view: 'diag',
      actions: [
        { label: '📋 报告', class: 'btn-ghost', onClick: () => showReport(r.data) },
        { label: '👌 知道了', class: 'btn-primary', onClick: () => Modal.close() }
      ]
    });
  }

  function reportText(st, diag) {
    const out = ['HostKeeper ' + (st.version || VERSION) + ' (' + (st.versionCode || VERSION_CODE) + ') 报告', ''];
    statusRows(st).forEach((row) => out.push(row[0] + ': ' + row[1]));
    if (st.conflicts && st.conflicts.length) out.push('冲突模块：' + st.conflicts.join('、'));
    if (diag && diag.checks) {
      out.push('', '健康检查');
      diag.checks.forEach((c) => out.push(diagIcon(c.level) + ' ' + c.title + ': ' + c.detail));
    }
    const logs = (S.logs || []).slice(-40);
    if (logs.length) {
      out.push('', '最近日志');
      logs.forEach((l) => out.push(new Date(l.t * 1000).toISOString().replace('T', ' ').slice(0, 19) + ' ' + l.l + ' ' + l.m));
    }
    return out.join('\n');
  }

  async function showReport(diag) {
    const r = await api('status');
    if (!r.ok) {
      toast(r.message, 'err');
      return;
    }
    await loadLogs();
    textSheet({ icon: '📋', title: '报告', text: reportText(r.data, diag), hint: '可粘贴到问题反馈中。它不包含个人数据，只有 HostKeeper 自身状态。' });
  }

  async function repairFlow() {
    if (S.busy || S.syncBusy) return;
    const ok = await confirmBox({
      icon: '🛠️',
      title: '修复 HostKeeper？',
      body: [para('将使用已缓存的列表和规则重新构建 hosts 文件，再次校验，并在需要时挂载。不会下载任何内容。', 'center')],
      ok: '🛠️ 修复'
    });
    if (!ok) return;
    Modal.close();
    setSyncBusy(true);
    const r = await api('repair');
    setSyncBusy(false);
    toast(r.message, r.ok ? 'ok' : 'err');
    refreshAll();
  }

  function extractDomain(raw, type) {
    let s = String(raw || '').trim();
    if (!s) return { err: ERR.empty };
    if (/\s/.test(s)) return { err: ERR.space };
    let wild = false;
    if (s.indexOf('*.') === 0) {
      if (type === 'block') return { err: ERR.wildblock };
      wild = true;
      s = s.slice(2);
    }
    if (s.indexOf('*') >= 0) return { err: type === 'block' ? ERR.wildblock : ERR.wildcard };
    const scheme = /^[a-z][a-z0-9+.-]*:\/\//i.test(s);
    if (!scheme) {
      const hostPart = s.split(/[/?#]/)[0];
      if (hostPart.indexOf(':') >= 0 || hostPart.charAt(0) === '[') return { err: ERR.port };
    }
    let host = '';
    try {
      host = new URL(scheme ? s : 'http://' + s).hostname;
    } catch (e) {
      return { err: ERR.invalid };
    }
    host = host.toLowerCase().replace(/\.$/, '');
    if (!host) return { err: ERR.empty };
    if (host.charAt(0) === '[' || host.indexOf(':') >= 0) return { err: ERR.port };
    if (/^[0-9.]+$/.test(host)) return { err: ERR.ip };
    if (host.length > 253) return { err: ERR.invalid };
    const labels = host.split('.');
    if (labels.length < 2) return { err: ERR.invalid };
    for (let i = 0; i < labels.length; i++) {
      const l = labels[i];
      if (l.length < 1 || l.length > 63) return { err: ERR.invalid };
      if (i < labels.length - 1) {
        if (!/^[a-z0-9_]([a-z0-9_-]*[a-z0-9_])?$/.test(l)) return { err: ERR.invalid };
      } else if (!/^[a-z]{2,}$/.test(l) && !/^xn--[a-z0-9]([a-z0-9-]*[a-z0-9])?$/.test(l)) {
        return { err: ERR.invalid };
      }
    }
    return { domain: (wild ? '*.' : '') + host, wild: wild };
  }

  function setRuleMsg(text, kind) {
    const m = $('rule-msg');
    m.textContent = text || '';
    m.className = 'field-msg' + (kind ? ' is-' + kind : '');
    m.title = text || '';
  }

  function previewRule() {
    const v = $('rule-input').value;
    if (!v.trim()) {
      setRuleMsg('', '');
      return;
    }
    const r = extractDomain(v, 'allow');
    if (r.domain && r.wild) setRuleMsg('→ ' + r.domain + ' 将放行 ' + r.domain.slice(2) + ' 及其所有子域', '');
    else if (r.domain && r.domain !== v.trim().toLowerCase()) setRuleMsg('→ ' + r.domain, '');
    else setRuleMsg('', '');
  }

  function takeRules(data) {
    if (data && data.rules) S.rules = { allow: data.rules.allow || [], block: data.rules.block || [] };
  }

  async function addRule(type, value) {
    if (S.busy || S.syncBusy) return false;
    const input = $('rule-input');
    const r = extractDomain(value === undefined ? input.value : value, type);
    if (r.err) {
      setRuleMsg(r.err, 'err');
      return false;
    }
    const other = type === 'allow' ? 'block' : 'allow';
    const cap = (t) => (t === 'allow' ? '放行' : '拦截');
    if (S.rules[type].indexOf(r.domain) >= 0) {
      setRuleMsg('⚠️ ' + r.domain + ' 已在你的' + cap(type) + '列表中。', 'err');
      return false;
    }
    if (S.rules[other].indexOf(r.domain) >= 0) {
      setRuleMsg('⚠️ 已在' + cap(other) + '列表中。请先在那里移除 ' + r.domain + '。', 'err');
      return false;
    }
    if (S.rules[type].length >= RULE_MAX) {
      setRuleMsg('📦 该列表已达到 ' + fmtNum(RULE_MAX) + ' 条规则上限，请先移除一些。', 'err');
      return false;
    }
    const btn = $(type === 'allow' ? 'rule-allow' : 'rule-block');
    const label = btn.textContent;
    btn.textContent = '⏳ 保存中…';
    setSyncBusy(true);
    const res = await api('rule-add', [type, r.domain]);
    setSyncBusy(false);
    btn.textContent = label;
    if (res.ok) {
      input.value = '';
      setRuleMsg('', '');
      takeRules(res.data);
      S.tab = type;
      renderRules();
      toast(res.message, 'ok');
      loadStatus();
      loadLogs();
      return true;
    }
    setRuleMsg(res.message, 'err');
    return false;
  }

  async function deleteRule(type, domain, btn) {
    if (S.busy || S.syncBusy) return false;
    if (btn) btn.disabled = true;
    setSyncBusy(true);
    const res = await api('rule-del', [type, domain]);
    setSyncBusy(false);
    if (res.ok) {
      takeRules(res.data);
      renderRules();
      toast(res.message, 'ok');
      loadStatus();
      loadLogs();
      return true;
    }
    if (btn) btn.disabled = false;
    toast(res.message, 'err');
    return false;
  }

  function hideLookup() {
    S.lookup = null;
    const box = $('lookup');
    box.hidden = true;
    clear(box);
  }

  function lookupAction(label, cls, fn) {
    const b = h('button', { class: 'btn btn-xs ' + cls, type: 'button', text: label });
    b.disabled = S.busy || S.syncBusy;
    b.addEventListener('click', async () => {
      const ok = await fn();
      if (ok) runLookup(S.lookup ? S.lookup.query : '');
    });
    return b;
  }

  function renderLookup(r) {
    const box = clear($('lookup'));
    const d = r.data || {};
    S.lookup = d;
    box.hidden = false;
    let cls = 'lookup';
    if (d.type === 'domain' && d.status === 'blocked') cls += ' is-blocked';
    else if (d.type === 'domain' && (d.status === 'clear' || d.status === 'allowed')) cls += ' is-clear';
    box.className = cls;
    box.appendChild(h('div', { class: 'lk-msg', text: r.message }));
    if (d.applied === 'pending') box.appendChild(h('div', { class: 'lk-sub', text: '🟡 这里显示的是已保存的设置，将在重启后生效。' }));
    if (d.type === 'keyword') {
      if (d.matchCount > 0) {
        const more = d.matchCount > d.matches.length ? ' 仅显示前 ' + d.matches.length + ' 个。' : '';
        box.appendChild(h('div', { class: 'lk-sub', text: '点击域名即可检查。' + more }));
        box.appendChild(h('div', { class: 'lk-chips' }, d.matches.map((m) => {
          const c = h('button', { class: 'chiplet', type: 'button', text: m });
          c.addEventListener('click', () => {
            $('rule-input').value = m;
            runLookup(m);
          });
          return c;
        })));
      }
      return;
    }
    if (d.subCount > 0) {
      const sample = d.subs.slice(0, 3).join(', ');
      box.appendChild(h('div', { class: 'lk-sub', text: '🧩 已拦截 ' + fmtNum(d.subCount) + ' 个子域，例如 ' + sample + '。' }));
    }
    const acts = [];
    if (d.status === 'blocked' && d.rule === 'block') acts.push(lookupAction('🗑️ 移除我的拦截规则', 'btn-ghost', () => deleteRule('block', d.domain)));
    else if (d.status === 'blocked') acts.push(lookupAction('✅ 放行它', 'btn-allow', () => addRule('allow', d.domain)));
    if (d.status === 'allowed' && d.ref) acts.push(lookupAction('🗑️ 移除我的放行规则', 'btn-ghost', () => deleteRule('allow', d.ref)));
    if (d.status === 'clear') acts.push(lookupAction('⛔ 拦截它', 'btn-block', () => addRule('block', d.domain)));
    if (d.subCount > 0 && d.status !== 'allowed' && d.status !== 'disabled') acts.push(lookupAction('✅ 放行所有子域', 'btn-allow', () => addRule('allow', '*.' + d.domain)));
    if (acts.length) box.appendChild(h('div', { class: 'lk-actions' }, acts));
  }

  async function runLookup(value) {
    const input = $('rule-input');
    const q = String(value === undefined ? input.value : value).trim();
    if (!q) {
      setRuleMsg('✏️ 请先输入域名或关键词。', 'err');
      hideLookup();
      return;
    }
    const btn = $('rule-check');
    btn.disabled = true;
    const r = await api('lookup', [q]);
    btn.disabled = false;
    if (!r.ok) {
      hideLookup();
      setRuleMsg(r.message, 'err');
      return;
    }
    setRuleMsg('', '');
    renderLookup(r);
  }

  function rulesAsText() {
    const out = [];
    S.rules.allow.forEach((d) => out.push('allow ' + d));
    S.rules.block.forEach((d) => out.push('block ' + d));
    return out.join('\n');
  }

  function exportRules() {
    const n = S.rules.allow.length + S.rules.block.length;
    if (!n) {
      toast('🌱 还没有可导出的规则。', 'info');
      return;
    }
    textSheet({ icon: '📤', title: '导出规则', text: rulesAsText(), hint: '共 ' + n + ' 条规则。请妥善保存这段文本，需要恢复时粘贴到 📥 导入规则。' });
  }

  function parseRules(text, fallback) {
    const out = { allow: [], block: [], skipped: 0 };
    const seen = {};
    String(text || '').split(/\r?\n/).forEach((raw) => {
      let line = raw;
      const hash = line.indexOf('#');
      if (hash >= 0) line = line.slice(0, hash);
      line = line.trim();
      if (!line) return;
      let type = fallback;
      let rest = line;
      const m = /^(allow|block)\s+(.*)$/i.exec(line);
      if (m) {
        type = m[1].toLowerCase();
        rest = m[2];
      } else if (/^(0\.0\.0\.0|127\.0\.0\.1)\s+/.test(line)) {
        type = 'block';
        rest = line.replace(/^\S+\s+/, '');
      } else if (line.charAt(0) === '+') {
        type = 'allow';
        rest = line.slice(1);
      } else if (line.charAt(0) === '-') {
        type = 'block';
        rest = line.slice(1);
      }
      rest.split(/[\s,;]+/).forEach((tok) => {
        if (!tok) return;
        const r = extractDomain(tok, type);
        if (r.err || seen[r.domain]) {
          out.skipped++;
          return;
        }
        seen[r.domain] = true;
        out[type].push(r.domain);
      });
    });
    return out;
  }

  async function sendImport(allow, block, mode) {
    const limit = 40000;
    const batches = [];
    let a = [];
    let b = [];
    let size = 0;
    const flush = () => {
      batches.push([a, b]);
      a = [];
      b = [];
      size = 0;
    };
    allow.forEach((d) => {
      if (size + d.length + 1 > limit) flush();
      a.push(d);
      size += d.length + 1;
    });
    block.forEach((d) => {
      if (size + d.length + 1 > limit) flush();
      b.push(d);
      size += d.length + 1;
    });
    if (a.length || b.length || !batches.length) flush();
    let last = null;
    let added = 0;
    let skipped = 0;
    for (let i = 0; i < batches.length; i++) {
      last = await api('rules-import', [batches[i][0].join(','), batches[i][1].join(','), i === 0 ? mode : 'merge']);
      const d = last.data || {};
      added += Number(d.added) || 0;
      skipped += (Number(d.invalid) || 0) + (Number(d.duplicate) || 0) + (Number(d.conflict) || 0) + (Number(d.limit) || 0);
      if (!last.ok && last.code !== 'import_nothing') break;
    }
    if (batches.length > 1 && last && (last.ok || last.code === 'import_nothing')) {
      return {
        ok: added > 0 || mode === 'replace',
        code: added > 0 || mode === 'replace' ? 'rules_imported' : 'import_nothing',
        message: (added > 0 || mode === 'replace' ? '📥 已导入 ' + added + ' 条规则。' : 'ℹ️ 没有新规则可导入。') + (skipped ? ' 已跳过 ' + skipped + ' 条。' : ''),
        data: last.data
      };
    }
    return last;
  }

  function importRules() {
    if (S.busy || S.syncBusy) return;
    let mode = 'merge';
    let fallback = S.tab;
    const ta = h('textarea', { class: 'area', spellcheck: 'false', autocapitalize: 'off', autocorrect: 'off', 'aria-label': '要导入的规则', placeholder: 'allow example.com\nallow *.cdn.example.com\nblock ads.example.net\n\n纯域名也可以，每行一个。' });
    const info = h('p', { class: 'fine', text: '粘贴导出的规则，或每行一个域名。' });
    const seg = (items, current, onPick) => {
      const box = h('div', { class: 'seg seg-2', role: 'tablist' });
      items.forEach((it) => {
        const b = h('button', { class: 'seg-btn' + (it[0] === current ? ' is-on' : ''), type: 'button', role: 'tab', 'aria-selected': it[0] === current ? 'true' : 'false', text: it[1] });
        b.addEventListener('click', () => {
          for (let i = 0; i < box.children.length; i++) {
            box.children[i].classList.toggle('is-on', box.children[i] === b);
            box.children[i].setAttribute('aria-selected', box.children[i] === b ? 'true' : 'false');
          }
          onPick(it[0]);
        });
        box.appendChild(b);
      });
      return box;
    };
    const refresh = () => {
      const p = parseRules(ta.value, fallback);
      if (!ta.value.trim()) {
        info.textContent = '粘贴导出的规则，或每行一个域名。';
        info.className = 'fine';
        return p;
      }
      info.textContent = '✅ ' + p.allow.length + ' 条放行 · ⛔ ' + p.block.length + ' 条拦截' + (p.skipped ? ' · 🚫 跳过 ' + p.skipped + ' 条' : '');
      info.className = 'fine' + (p.allow.length + p.block.length ? ' is-ok' : ' is-err');
      return p;
    };
    ta.addEventListener('input', refresh);
    const submit = async () => {
      const p = refresh();
      if (!p.allow.length && !p.block.length && mode !== 'replace') {
        info.textContent = '✏️ 还没有可导入的内容。';
        info.className = 'fine is-err';
        return;
      }
      if (mode === 'replace') {
        const sure = await confirmBox({
          icon: '♻️',
          title: '替换全部规则？',
          body: [para('当前的 ' + (S.rules.allow.length + S.rules.block.length) + ' 条规则将被移除，替换为你粘贴的 ' + (p.allow.length + p.block.length) + ' 条规则。', 'center')],
          ok: '♻️ 替换',
          okClass: 'btn-danger'
        });
        if (!sure) return;
      }
      Modal.close();
      setSyncBusy(true);
      const r = await sendImport(p.allow, p.block, mode);
      setSyncBusy(false);
      takeRules(r.data);
      renderRules();
      toast(r.message, r.ok ? 'ok' : (r.code === 'import_nothing' ? 'info' : 'err'));
      loadStatus();
      loadLogs();
    };
    Modal.show({
      icon: '📥',
      title: '导入规则',
      body: [
        ta,
        info,
        h('div', { class: 'set-desc', text: '未标注 allow 或 block 的行按以下类型处理：' }),
        seg([['allow', '✅ 放行'], ['block', '⛔ 拦截']], fallback, (v) => { fallback = v; refresh(); }),
        h('div', { class: 'set-desc', text: '如何处理当前规则？' }),
        seg([['merge', '➕ 保留并追加'], ['replace', '♻️ 全部替换']], mode, (v) => { mode = v; })
      ],
      view: 'import',
      actions: [
        { label: '↩️ 暂不', class: 'btn-ghost', onClick: () => Modal.close() },
        { label: '📥 导入', class: 'btn-primary', onClick: submit }
      ]
    });
  }

  async function refreshMeta(id) {
    if (id && cards[id]) {
      cards[id].retry.disabled = true;
    }
    const r = await api('meta-refresh', id ? [id] : []);
    if (!r.ok) {
      toast(r.message, 'err');
      if (id && cards[id]) cards[id].retry.disabled = false;
      return;
    }
    if (S.lists) {
      S.refreshing = true;
      S.lists.lists.forEach((l) => {
        if (!id || l.id === id) {
          l.busy = true;
          l.error = '';
          l.count = null;
        }
      });
      if (!id) {
        (S.lists.addons || []).forEach((a) => {
          a.busy = true;
          a.error = '';
        });
      }
      renderLists();
    }
    if (!id) toast(r.message, 'info');
    scheduleLists(800);
  }

  async function clearLogs() {
    const ok = await confirmBox({
      icon: '🧹',
      title: '清空全部日志？',
      body: [para('这会移除所有日志条目，不会更改列表、规则或 hosts 文件。', 'center')],
      ok: '🧹 清空日志',
      okClass: 'btn-danger'
    });
    if (!ok) return;
    Modal.close();
    const r = await api('logs-clear');
    toast(r.message, r.ok ? 'ok' : 'err');
    loadLogs();
  }

  function copyLogs() {
    const logs = visibleLogs();
    if (!logs.length) {
      toast('📭 没有可复制的内容。', 'info');
      return;
    }
    const text = logs.map((l) => new Date(l.t * 1000).toISOString().replace('T', ' ').slice(0, 19) + ' ' + l.l + ' ' + l.m).join('\n');
    textSheet({ icon: '📜', title: '复制日志', text: text, hint: '共 ' + logs.length + ' 条日志。' });
  }

  async function openLink(id) {
    const r = await api('open', [id]);
    toast(r.message, r.ok ? 'info' : 'err');
  }

  async function loadStatus() {
    const r = await api('status');
    if (r.ok) {
      S.status = r.data;
      if (r.data.op && r.data.op.running) S.busy = true;
      renderStatus();
      if (S.lists) renderLists();
      handleOp(r.data.op);
    }
    return r;
  }

  let listsTimer = 0;

  function scheduleLists(ms) {
    clearTimeout(listsTimer);
    listsTimer = setTimeout(loadLists, ms);
  }

  async function loadLists() {
    const r = await api('lists');
    if (r.ok) {
      S.lists = r.data;
      S.refreshing = !!r.data.refreshing;
      renderLists();
      if (S.refreshing) scheduleLists(1500);
    }
    return r;
  }

  async function loadRules() {
    const r = await api('rules');
    if (r.ok) {
      S.rules = { allow: r.data.allow || [], block: r.data.block || [] };
      renderRules();
    }
    return r;
  }

  async function loadLogs() {
    const r = await api('logs');
    if (r.ok) {
      S.logs = r.data.logs || [];
      renderLogs();
    }
    return r;
  }

  function refreshAll() {
    loadStatus();
    loadLists();
    loadRules();
    loadLogs();
  }

  function setupTheme() {
    const btn = $('theme-btn');
    const meta = document.querySelector('meta[name="theme-color"]');
    const apply = (t) => {
      document.documentElement.setAttribute('data-theme', t);
      btn.textContent = t === 'dark' ? '☀️' : '🌙';
      btn.setAttribute('aria-label', t === 'dark' ? '切换到浅色主题' : '切换到深色主题');
      if (meta) meta.setAttribute('content', t === 'dark' ? '#06080d' : '#eef2f7');
    };
    apply(document.documentElement.getAttribute('data-theme') === 'light' ? 'light' : 'dark');
    btn.addEventListener('click', () => {
      const next = document.documentElement.getAttribute('data-theme') === 'light' ? 'dark' : 'light';
      apply(next);
      store.set('hostkeeper-theme', next);
    });
  }

  function setupGuards() {
    const allowed = (t) => {
      const n = t && t.nodeType === 3 ? t.parentElement : t;
      return !!(n && n.closest && n.closest('input, textarea'));
    };
    ['contextmenu', 'copy', 'cut', 'selectstart', 'dragstart'].forEach((ev) => {
      document.addEventListener(ev, (e) => {
        if (!allowed(e.target)) e.preventDefault();
      });
    });
  }

  function setupLite() {
    const mem = Number(navigator.deviceMemory) || 0;
    const cores = Number(navigator.hardwareConcurrency) || 0;
    if ((mem && mem <= 2) || (cores && cores <= 4)) document.documentElement.classList.add('lite');
  }

  function bindEvents() {
    const nav = document.querySelectorAll('.chip');
    for (let i = 0; i < nav.length; i++) {
      nav[i].addEventListener('click', (e) => {
        e.preventDefault();
        const id = (nav[i].getAttribute('href') || '').slice(1);
        const target = $(id);
        if (!target) return;
        const reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        target.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' });
      });
    }
    $('ribbon-btn').addEventListener('click', () => {
      const mode = $('ribbon-btn').getAttribute('data-mode');
      if (mode === 'reboot' || mode === 'inactive') rebootFlow();
      else if (mode === 'setup' && S.status) runUpdate();
    });
    $('lists-refresh').addEventListener('click', () => refreshMeta(''));
    $('addon-apply').addEventListener('click', applyAddons);
    $('addon-reset').addEventListener('click', resetAddons);
    $('rule-input').addEventListener('input', () => {
      previewRule();
      if (S.lookup) hideLookup();
    });
    $('rule-input').addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        $('rule-input').blur();
        runLookup();
      }
    });
    $('rule-allow').addEventListener('click', () => addRule('allow'));
    $('rule-block').addEventListener('click', () => addRule('block'));
    $('rule-check').addEventListener('click', () => runLookup());
    $('rules-import').addEventListener('click', importRules);
    $('rules-export').addEventListener('click', exportRules);
    $('rule-filter').addEventListener('input', () => {
      S.ruleFilter = $('rule-filter').value;
      renderRules();
    });
    $('tab-allow').addEventListener('click', () => { S.tab = 'allow'; renderRules(); });
    $('tab-block').addEventListener('click', () => { S.tab = 'block'; renderRules(); });
    $('act-update').addEventListener('click', runUpdate);
    $('act-status').addEventListener('click', showStatusDialog);
    $('act-toggle').addEventListener('click', toggleBlocker);
    $('act-diag').addEventListener('click', showDiag);
    $('act-settings').addEventListener('click', showSettings);
    $('act-repair').addEventListener('click', repairFlow);
    $('logs-refresh').addEventListener('click', () => { S.logSig = ''; loadLogs(); });
    $('logs-copy').addEventListener('click', copyLogs);
    $('logs-clear').addEventListener('click', clearLogs);
    const fs = document.querySelectorAll('.filter');
    for (let i = 0; i < fs.length; i++) {
      fs[i].addEventListener('click', () => setLogLevel(fs[i].getAttribute('data-level')));
    }
    $('gate-retry').addEventListener('click', retryGate);
    $('mini').addEventListener('click', () => {
      if (S.op && S.op.running) {
        S.opView = true;
        showProgress(S.op);
      }
    });
    const links = document.querySelectorAll('[data-link]');
    for (let i = 0; i < links.length; i++) {
      links[i].addEventListener('click', () => openLink(links[i].getAttribute('data-link')));
    }
    document.addEventListener('visibilitychange', () => {
      if (document.hidden || !S.ready || S.gate) return;
      loadStatus();
      if (S.busy) schedulePoll(0);
    });
    setInterval(() => {
      if (!document.hidden && S.ready && !S.gate) loadLogs();
    }, 10000);
    setInterval(() => {
      if (!document.hidden && S.ready && !S.gate && !S.busy) loadStatus();
    }, 60000);
  }

  async function start() {
    if (Bridge.mode === 'http' && Bridge.framed()) {
      showGate('framed');
      return;
    }
    if (Bridge.mode === 'http' && !Bridge.hasToken()) {
      showGate('no_token');
      return;
    }
    const r = await loadStatus();
    if (!r.ok) {
      if (!S.gate) showGate('bridge');
      return;
    }
    S.ready = true;
    await Promise.all([loadLists(), loadRules(), loadLogs()]);
  }

  function init() {
    setupLite();
    setupTheme();
    setupGuards();
    bindEvents();
    start();
  }

  init();
})();
