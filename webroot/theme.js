(() => {
  'use strict';
  try {
    const t = window.localStorage.getItem('hostkeeper-theme');
    if (t === 'light' || t === 'dark') document.documentElement.setAttribute('data-theme', t);
  } catch (e) {
    document.documentElement.setAttribute('data-theme', 'dark');
  }
})();
