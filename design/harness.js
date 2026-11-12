// Mockup harness: the fixed part, the same for every product. Do not fill this in.
// It draws the mockup control bar and the device frame, switches Desktop/Phone,
// runs the jump buttons, resets, and shows toasts. Everything about the product
// lives in product.js, which calls mockup({...}) once.
// Each direction's html loads this file first, then product.js. Mockup only, not production code.

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

let state = {}; // product state from initial(), plus `viewport`
let epoch = 0; // Reset bumps this, so a flow still sleeping stops quietly instead of leaving state behind
const sleep = (ms) => {
  const e = epoch;
  return new Promise((r) => setTimeout(() => e === epoch && r(), ms));
};

let P; // the product passed to mockup()

function toast(html, tone = '') {
  const t = $('#toast');
  t.className = `toast show ${tone}`;
  t.innerHTML = html;
  clearTimeout(toast.h);
  toast.h = setTimeout(() => (t.className = 'toast'), 4800);
}

function render() {
  const d = $('#device');
  d.className = `device vp-${state.viewport}`;
  $$('[data-vp]').forEach((b) => b.classList.toggle('on', b.dataset.vp === state.viewport));
  P.render(d);
}

function reset() {
  epoch++;
  clearTimeout(toast.h);
  $('#toast').className = 'toast'; // no leftover state after Reset
  state = { ...P.initial(), viewport: state.viewport }; // keep the viewport
  render();
}

// product: { initial, markup, render(device), moments: { key: [label, fn] }, click?(event), viewport?() }
function mockup(product) {
  P = product;
  const moments = { reset: ['Reset', reset], ...product.moments };
  document.body.insertAdjacentHTML(
    'afterbegin',
    `<nav class="mock-controls" aria-label="Mockup controls">
      <strong>${document.title}</strong>
      <span class="seg"><button data-vp="desktop">Desktop</button><button data-vp="phone">Phone</button></span>
      <span class="seg">${Object.entries(moments).map(([k, [label]]) => `<button data-jump="${k}">${label}</button>`).join('')}</span>
      <span class="others"><a href="index.html">All directions</a></span>
    </nav>
    <div class="stage"><div class="device" id="device">${product.markup()}<div class="toast" id="toast" role="status" aria-live="polite"></div></div></div>`,
  );
  document.addEventListener('click', (e) => {
    const t = e.target.closest('[data-vp], [data-jump]');
    if (t?.dataset.vp) {
      state.viewport = t.dataset.vp;
      P.viewport?.();
      render();
    } else if (t?.dataset.jump) moments[t.dataset.jump][1]();
    else P.click?.(e);
  });
  // Narrow real screens (a phone opening the shared link) start in the phone view.
  state = { ...P.initial(), viewport: matchMedia('(max-width: 700px)').matches ? 'phone' : 'desktop' };
  render();
}
