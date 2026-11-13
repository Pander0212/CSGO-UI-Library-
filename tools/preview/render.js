/*
  Renders GUI dumps produced by the Luau mock (tools/preview/out/*.json) to PNG screenshots.
  It re-implements the parts of Roblox's GUI layout the library uses: UDim2 size/position,
  AnchorPoint, AutomaticSize, UIListLayout, UIPadding, UICorner, UIStroke, UIGradient, UIScale,
  UISizeConstraint, ZIndex (sibling), ClipsDescendants, text alignment/wrapping/truncation and a
  flat-shaded projection of the parts inside ViewportFrames.

    node tools/preview/render.js [name ...] [--scale 2] [--crop]
*/
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const OUT = path.join(__dirname, 'out');
const SHOTS = path.join(__dirname, '..', '..', 'docs', 'screenshots');

const pageScript = String.raw`
const FONT = {
  Code:['Inconsolata',500], RobotoMono:['Roboto Mono',400], Gotham:['Montserrat',500], GothamMedium:['Montserrat',600],
  GothamBold:['Montserrat',700], GothamBlack:['Montserrat',900], SourceSans:['Source Sans 3',400],
  SourceSansSemibold:['Source Sans 3',600], SourceSansBold:['Source Sans 3',700], Ubuntu:['Ubuntu',400],
  Roboto:['Roboto',400], RobotoCondensed:['Roboto Condensed',400], Arial:['Arimo',400], ArialBold:['Arimo',700],
  Nunito:['Nunito',600], Montserrat:['Montserrat',500], BuilderSans:['Inter',400], BuilderSansMedium:['Inter',500],
  BuilderSansBold:['Inter',700], Jura:['Jura',600], Michroma:['Michroma',400], Oswald:['Oswald',500],
  Arimo:['Arimo',400], ArimoBold:['Arimo',700], Highway:['Oswald',400], SciFi:['Michroma',400], Zekton:['Michroma',400],
  Sarpanch:['Oswald',500], TitilliumWeb:['Titillium Web',600]
};
const GUI = new Set(['Frame','TextLabel','TextButton','TextBox','ImageLabel','ImageButton','ScrollingFrame','ViewportFrame','CanvasGroup']);
const TEXT = new Set(['TextLabel','TextButton','TextBox']);
const cv = document.createElement('canvas').getContext('2d');
function fontOf(p){ const f = FONT[p.Font] || ['Montserrat',500]; return f; }
function fontCss(p, size){ const f = fontOf(p); return f[1] + ' ' + (size||p.TextSize||14) + 'px "' + f[0] + '"'; }
function textW(p, s, size){ cv.font = fontCss(p, size); return cv.measureText(s).width; }
function rgba(c, t){ if(!c) return 'transparent'; return 'rgba('+c[0]+','+c[1]+','+c[2]+','+(1-(t||0)).toFixed(3)+')'; }
function mods(n){ const m = {strokes:[]}; n.k.forEach((k,i)=>{ k._i = i; if(k.c==='UIStroke') m.strokes.push(k); else if(!GUI.has(k.c)) { if(!m[k.c]) m[k.c]=k; } }); return m; }
function udim(u, total){ return u ? u[0]*total + u[1] : 0; }
function padOf(m, w, h){ if(!m.UIPadding) return {t:0,b:0,l:0,r:0}; const p = m.UIPadding.p; return {t:udim(p.PaddingTop,h), b:udim(p.PaddingBottom,h), l:udim(p.PaddingLeft,w), r:udim(p.PaddingRight,w)}; }
function visKids(n){ return n.k.filter(k=>GUI.has(k.c) && k.p.Visible !== false); }
function displayText(p, cls){ if(cls==='TextBox' && (!p.Text || p.Text==='')) return {s:p.PlaceholderText||'', ph:true}; return {s: p.Text||'', ph:false}; }
function wrapLines(p, s, width){
  const out = [];
  for (const para of s.split('\n')) {
    const words = para.split(' '); let line = '';
    for (const w of words) { const t = line ? line + ' ' + w : w; if (textW(p, t) > width && line) { out.push(line); line = w; } else line = t; }
    out.push(line);
  }
  return out;
}
function textSize(n, w){
  const p = n.p; const t = displayText(p, n.c).s; const size = p.TextSize || 14;
  if (p.TextWrapped && w > 0) { const lines = wrapLines(p, t, w); return {w: Math.max(...lines.map(l=>textW(p,l))), h: lines.length * Math.round(size*1.15)}; }
  return {w: textW(p, t), h: size};
}
function contentSize(n, kids, m, pad, w, h){
  let cw = 0, ch = 0;
  if (TEXT.has(n.c)) { const ts = textSize(n, w - pad.l - pad.r); cw = ts.w; ch = ts.h; }
  const L = m.UIListLayout && m.UIListLayout.p;
  const vis = kids.filter(k=>k.p.Visible!==false);
  if (L) {
    const horiz = L.FillDirection === 'Horizontal';
    const gap = udim(L.Padding, horiz ? w : h);
    let main = 0, cross = 0;
    vis.forEach((k,i)=>{ main += (horiz? k._w : k._h) + (i>0?gap:0); cross = Math.max(cross, horiz? k._h : k._w); });
    if (horiz) { cw = Math.max(cw, main); ch = Math.max(ch, cross); } else { ch = Math.max(ch, main); cw = Math.max(cw, cross); }
  } else {
    vis.forEach(k=>{ const pos = k.p.Position||[0,0,0,0]; const a = k.p.AnchorPoint||[0,0];
      cw = Math.max(cw, pos[1] + k._w*(1-a[0])); ch = Math.max(ch, pos[3] + k._h*(1-a[1])); });
  }
  return {w: cw + pad.l + pad.r, h: ch + pad.t + pad.b};
}
function layout(n, pw, ph){
  const p = n.p; const m = mods(n); n._m = m;
  const S = p.Size || [0,100,0,100];
  let w = pw*S[0] + S[1], h = ph*S[2] + S[3];
  const auto = p.AutomaticSize || 'None';
  const kids = n.k.filter(k=>GUI.has(k.c));
  const run = ()=>{ const pad = padOf(m, w, h); kids.forEach(k=>layout(k, w-pad.l-pad.r, h-pad.t-pad.b)); return pad; };
  let pad = run();
  if (auto !== 'None') {
    const c = contentSize(n, kids, m, pad, w, h);
    if (auto === 'X' || auto === 'XY') w = Math.max(w, c.w);
    if (auto === 'Y' || auto === 'XY') h = Math.max(h, c.h);
    pad = run();
    const c2 = contentSize(n, kids, m, pad, w, h);
    if (auto === 'Y' || auto === 'XY') h = Math.max(h, c2.h);
  }
  if (m.UISizeConstraint) { const sc = m.UISizeConstraint.p; if (sc.MaxSize) { w = Math.min(w, sc.MaxSize[0]||w); h = Math.min(h, sc.MaxSize[1]||h); } }
  n._w = w; n._h = h;
  const cw = w - pad.l - pad.r, ch = h - pad.t - pad.b;
  const L = m.UIListLayout && m.UIListLayout.p;
  const G = m.UIGridLayout && m.UIGridLayout.p;
  if (G) {
    const cs = G.CellSize || [0,100,0,100], cp = G.CellPadding || [0,5,0,5];
    const cwid = cw*cs[0]+cs[1], chei = ch*cs[2]+cs[3], gx = cw*cp[0]+cp[1], gy = ch*cp[2]+cp[3];
    const perRow = Math.max(1, Math.floor((cw + gx) / (cwid + gx)));
    const vis = kids.filter(k=>k.p.Visible!==false).sort((a,b)=>(a.p.LayoutOrder||0)-(b.p.LayoutOrder||0) || a._i-b._i);
    vis.forEach((k,i)=>{ const keep = k.p.Size; k.p.Size = [0,cwid,0,chei]; layout(k, cw, ch); k.p.Size = keep; k._x = pad.l + (i%perRow)*(cwid+gx); k._y = pad.t + Math.floor(i/perRow)*(chei+gy); });
  } else if (L) {
    const horiz = L.FillDirection === 'Horizontal';
    const gap = udim(L.Padding, horiz ? cw : ch);
    const vis = kids.filter(k=>k.p.Visible!==false).sort((a,b)=>(a.p.LayoutOrder||0)-(b.p.LayoutOrder||0) || a._i-b._i);
    let total = 0; vis.forEach((k,i)=>{ total += (horiz? k._w:k._h) + (i>0?gap:0); });
    let cur;
    if (horiz) { const ha = L.HorizontalAlignment || 'Left'; cur = pad.l + (ha==='Center' ? (cw-total)/2 : ha==='Right' ? cw-total : 0); }
    else { const va = L.VerticalAlignment || 'Top'; cur = pad.t + (va==='Center' ? (ch-total)/2 : va==='Bottom' ? ch-total : 0); }
    vis.forEach(k=>{
      if (horiz) { k._x = cur; const va = L.VerticalAlignment || 'Top'; k._y = pad.t + (va==='Center' ? (ch-k._h)/2 : va==='Bottom' ? ch-k._h : 0); cur += k._w + gap; }
      else { k._y = cur; const ha = L.HorizontalAlignment || 'Left'; k._x = pad.l + (ha==='Center' ? (cw-k._w)/2 : ha==='Right' ? cw-k._w : 0); cur += k._h + gap; }
    });
  } else {
    kids.forEach(k=>{ const P = k.p.Position||[0,0,0,0]; const A = k.p.AnchorPoint||[0,0];
      k._x = pad.l + cw*P[0] + P[1] - A[0]*k._w; k._y = pad.t + ch*P[2] + P[3] - A[1]*k._h; });
  }
}
function gradientCss(g, bg, bgT){
  const gp = g.p; if (gp.Enabled === false) return null;
  const cs = (gp.Color && gp.Color.__cs) || [[0,255,255,255],[1,255,255,255]];
  const ns = (gp.Transparency && gp.Transparency.__ns) || [[0,0],[1,0]];
  const tAt = (t)=>{ for (let i=0;i<ns.length-1;i++){ const a=ns[i], b=ns[i+1]; if (t>=a[0] && t<=b[0]) { const f=(t-a[0])/((b[0]-a[0])||1); return a[1]+(b[1]-a[1])*f; } } return ns[ns.length-1][1]; };
  const stops = new Set(cs.map(k=>k[0]).concat(ns.map(k=>k[0])));
  const cAt = (t)=>{ for (let i=0;i<cs.length-1;i++){ const a=cs[i], b=cs[i+1]; if (t>=a[0] && t<=b[0]) { const f=(t-a[0])/((b[0]-a[0])||1); return [0,1,2].map(j=>a[j+1]+(b[j+1]-a[j+1])*f); } } const l=cs[cs.length-1]; return [l[1],l[2],l[3]]; };
  const list = [...stops].sort((a,b)=>a-b).map(t=>{ const c = cAt(t); const mul = c.map((v,j)=>Math.round(v*bg[j]/255)); const alpha = (1-bgT)*(1-tAt(t)); return 'rgba('+mul.join(',')+','+alpha.toFixed(3)+') '+(t*100).toFixed(1)+'%'; });
  return 'linear-gradient(' + ((gp.Rotation||0)+90) + 'deg,' + list.join(',') + ')';
}
function renderViewport(n, el){
  const cam = n.p.Camera; if (!cam) return;
  const parts = []; const walk = (x)=>{ x.k.forEach(k=>{ if (k.c==='Part') parts.push(k); walk(k); }); }; walk(n);
  const C = cam.CFrame; const cp = [C[0],C[1],C[2]]; const R = C.slice(3);
  const w = n._w, h = n._h; const f = (h/2)/Math.tan((cam.FieldOfView||70)*Math.PI/360);
  const toCam = (v)=>{ const d=[v[0]-cp[0],v[1]-cp[1],v[2]-cp[2]]; return [R[0]*d[0]+R[3]*d[1]+R[6]*d[2], R[1]*d[0]+R[4]*d[1]+R[7]*d[2], R[2]*d[0]+R[5]*d[1]+R[8]*d[2]]; };
  const proj = (v)=>{ const r=toCam(v); const depth=Math.max(-r[2],0.01); return [w/2 + r[0]*f/depth, h/2 - r[1]*f/depth, depth]; };
  const faces = [];
  const light = (n.p.LightDirection)||[-1,-1,-1]; const ll = Math.hypot(...light); const L=[light[0]/ll,light[1]/ll,light[2]/ll];
  parts.forEach(pt=>{
    if ((pt.p.Transparency||0) >= 1) return;
    const cf = pt.p.CFrame, s = pt.p.Size; const pos=[cf[0],cf[1],cf[2]], r=cf.slice(3);
    const world = (lx,ly,lz)=>[pos[0]+r[0]*lx+r[1]*ly+r[2]*lz, pos[1]+r[3]*lx+r[4]*ly+r[5]*lz, pos[2]+r[6]*lx+r[7]*ly+r[8]*lz];
    const hx=s[0]/2, hy=s[1]/2, hz=s[2]/2;
    const defs = [[[1,0,0],[[hx,-hy,-hz],[hx,hy,-hz],[hx,hy,hz],[hx,-hy,hz]]],[[-1,0,0],[[-hx,-hy,-hz],[-hx,-hy,hz],[-hx,hy,hz],[-hx,hy,-hz]]],
      [[0,1,0],[[-hx,hy,-hz],[-hx,hy,hz],[hx,hy,hz],[hx,hy,-hz]]],[[0,-1,0],[[-hx,-hy,-hz],[hx,-hy,-hz],[hx,-hy,hz],[-hx,-hy,hz]]],
      [[0,0,1],[[-hx,-hy,hz],[hx,-hy,hz],[hx,hy,hz],[-hx,hy,hz]]],[[0,0,-1],[[-hx,-hy,-hz],[-hx,hy,-hz],[hx,hy,-hz],[hx,-hy,-hz]]]];
    defs.forEach(([nl, cs])=>{
      const nw = [r[0]*nl[0]+r[1]*nl[1]+r[2]*nl[2], r[3]*nl[0]+r[4]*nl[1]+r[5]*nl[2], r[6]*nl[0]+r[7]*nl[1]+r[8]*nl[2]];
      const center = world(nl[0]*hx, nl[1]*hy, nl[2]*hz);
      const toC = [cp[0]-center[0], cp[1]-center[1], cp[2]-center[2]];
      if (nw[0]*toC[0]+nw[1]*toC[1]+nw[2]*toC[2] <= 0) return;
      const pts = cs.map(c=>proj(world(...c)));
      const depth = pts.reduce((a,b)=>a+b[2],0)/4;
      const lambert = Math.max(0, -(nw[0]*L[0]+nw[1]*L[1]+nw[2]*L[2]));
      const k = 0.55 + 0.45*lambert;
      const col = pt.p.Color.map(v=>Math.round(Math.min(255, v*k)));
      faces.push({pts, depth, col, t: pt.p.Transparency||0});
    });
  });
  faces.sort((a,b)=>b.depth-a.depth);
  const svg = document.createElementNS('http://www.w3.org/2000/svg','svg');
  svg.setAttribute('width', w); svg.setAttribute('height', h); svg.style.position='absolute'; svg.style.left='0'; svg.style.top='0';
  faces.forEach(fc=>{ const poly = document.createElementNS('http://www.w3.org/2000/svg','polygon');
    poly.setAttribute('points', fc.pts.map(p=>p[0].toFixed(1)+','+p[1].toFixed(1)).join(' '));
    poly.setAttribute('fill', 'rgb('+fc.col.join(',')+')'); poly.setAttribute('fill-opacity', (1-fc.t).toFixed(2));
    poly.setAttribute('stroke', 'rgba(0,0,0,0.25)'); poly.setAttribute('stroke-width','0.5'); svg.appendChild(poly); });
  el.appendChild(svg);
}
function render(n, parentEl, parentNode){
  const p = n.p; const m = n._m;
  const el = document.createElement('div');
  el.className = 'g ' + n.c; el.dataset.name = p.Name || '';
  const s = el.style;
  s.left = (n._x||0)+'px'; s.top = (n._y||0)+'px'; s.width = n._w+'px'; s.height = n._h+'px';
  s.zIndex = (p.ZIndex === undefined ? 1 : p.ZIndex);
  const bgT = p.BackgroundTransparency === undefined ? 0 : p.BackgroundTransparency;
  const bg = p.BackgroundColor3 || [163,162,165];
  if (bgT < 1) s.background = rgba(bg, bgT);
  if (m.UIGradient && bgT < 1) { const g = gradientCss(m.UIGradient, bg, bgT); if (g) { s.background = g; } }
  if (m.UICorner) { const r = udim(m.UICorner.p.CornerRadius, Math.min(n._w, n._h)); s.borderRadius = Math.min(r, Math.min(n._w,n._h)/2) + 'px'; }
  const shadows = []; const textShadows = [];
  m.strokes.forEach(st=>{ const sp = st.p; if (sp.Enabled === false) return; const c = rgba(sp.Color||[0,0,0], sp.Transparency||0); const t = sp.Thickness||1;
    if (TEXT.has(n.c) && sp.ApplyStrokeMode !== 'Border') { textShadows.push((-t)+'px 0 '+c, t+'px 0 '+c, '0 '+(-t)+'px '+c, '0 '+t+'px '+c); }
    else shadows.push('0 0 0 ' + t + 'px ' + c); });
  if (shadows.length) s.boxShadow = shadows.join(',');
  if (p.ClipsDescendants || n.c === 'ScrollingFrame') s.overflow = 'hidden';
  const tf = [];
  if (m.UIScale && m.UIScale.p.Scale !== 1) { tf.push('scale(' + m.UIScale.p.Scale + ')'); const a = p.AnchorPoint||[0,0]; s.transformOrigin = (a[0]*100)+'% '+(a[1]*100)+'%'; }
  if (p.Rotation) tf.push('rotate(' + p.Rotation + 'deg)');
  if (tf.length) s.transform = tf.join(' ');
  if (TEXT.has(n.c)) {
    const t = displayText(p, n.c);
    const span = document.createElement('span');
    const pad = padOf(m, n._w, n._h);
    s.display = 'flex'; s.boxSizing = 'border-box';
    s.padding = pad.t+'px '+pad.r+'px '+pad.b+'px '+pad.l+'px';
    s.alignItems = {Top:'flex-start', Bottom:'flex-end'}[p.TextYAlignment] || 'center';
    s.justifyContent = {Left:'flex-start', Right:'flex-end'}[p.TextXAlignment] || 'center';
    let size = p.TextSize || 14;
    if (p.TextScaled) { const avail = n._w - pad.l - pad.r; size = Math.max(6, Math.min(n._h*0.8, 100)); while (size > 6 && textW(p, t.s, size) > avail) size -= 1; }
    span.textContent = t.s;
    span.style.font = fontCss(p, size); span.style.lineHeight = Math.round(size*1.15)+'px';
    span.style.color = t.ph ? rgba(p.PlaceholderColor3||[178,178,178], 0) : rgba(p.TextColor3||[27,42,53], p.TextTransparency||0);
    span.style.textAlign = {Left:'left', Right:'right'}[p.TextXAlignment] || 'center';
    span.style.whiteSpace = p.TextWrapped ? 'pre-wrap' : 'pre';
    if (p.TextWrapped) span.style.width = '100%';
    if (p.TextTruncate === 'AtEnd') { span.style.overflow='hidden'; span.style.textOverflow='ellipsis'; span.style.maxWidth='100%'; }
    if (p.TextStrokeTransparency !== undefined && p.TextStrokeTransparency < 1) { const c = rgba(p.TextStrokeColor3||[0,0,0], p.TextStrokeTransparency); textShadows.push('-1px 0 '+c,'1px 0 '+c,'0 -1px '+c,'0 1px '+c); }
    if (textShadows.length) span.style.textShadow = textShadows.join(',');
    el.appendChild(span);
  }
  if ((n.c === 'ImageLabel' || n.c === 'ImageButton') && p.Image) { el.style.backgroundImage = 'repeating-linear-gradient(45deg, rgba(255,255,255,.08) 0 4px, transparent 4px 8px)'; }
  if (n.c === 'ViewportFrame') renderViewport(n, el);
  parentEl.appendChild(el);
  let inner = el;
  if (n.c === 'ScrollingFrame' && p.CanvasPosition && (p.CanvasPosition[0] || p.CanvasPosition[1])) {
    inner = document.createElement('div'); inner.className = 'g'; inner.style.left = (-p.CanvasPosition[0])+'px'; inner.style.top = (-p.CanvasPosition[1])+'px'; inner.style.width = '100%'; inner.style.height = '100%'; el.appendChild(inner);
  }
  n.k.filter(k=>GUI.has(k.c) && k.p.Visible !== false).forEach(k=>render(k, inner, n));
}
window.draw = function(data){
  const [W, H] = data.viewport; const root = data.root;
  const stage = document.getElementById('stage'); stage.style.width = W+'px'; stage.style.height = H+'px';
  const screen = root.k.find(k=>k.p.Name==='Root') || root;
  const node = {c:'Frame', p:{Size:[0,W,0,H], BackgroundTransparency:1, Name:'Screen'}, k:[screen]};
  layout(node, W, H); render(node, stage, null);
};
`;

const html = `<!doctype html><html><head><meta charset="utf-8">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inconsolata:wght@400;500;700&family=Roboto+Mono:wght@400;500&family=Montserrat:wght@400;500;600;700;900&family=Source+Sans+3:wght@400;600;700&family=Inter:wght@400;500;700&family=Ubuntu&family=Roboto&family=Roboto+Condensed&family=Nunito:wght@600&family=Oswald:wght@400;500&family=Jura:wght@600&family=Michroma&family=Arimo:wght@400;700&family=Titillium+Web:wght@600&display=block" rel="stylesheet">
<style>
html,body{margin:0;padding:0;background:#0b0d10;}
#stage{position:relative;overflow:hidden;background:
 radial-gradient(1200px 600px at 70% 20%, rgba(90,120,160,.35), transparent 60%),
 radial-gradient(900px 500px at 15% 90%, rgba(60,90,60,.35), transparent 60%),
 linear-gradient(180deg,#3a4a5c 0%,#5d6f63 55%,#3d4a3a 56%,#2b3328 100%);}
.g{position:absolute;box-sizing:border-box;}
</style></head><body><div id="stage"></div><script>${pageScript}</script></body></html>`;

(async () => {
  const args = process.argv.slice(2);
  const scale = args.includes('--scale') ? Number(args[args.indexOf('--scale') + 1]) : 1;
  const names = args.filter((a, i) => !a.startsWith('--') && !(args[i - 1] === '--scale'));
  const files = fs.readdirSync(OUT).filter(f => f.endsWith('.json')).map(f => f.slice(0, -5)).filter(n => !names.length || names.includes(n));
  fs.mkdirSync(SHOTS, { recursive: true });
  const browser = await chromium.launch();
  for (const name of files) {
    const data = JSON.parse(fs.readFileSync(path.join(OUT, name + '.json'), 'utf8'));
    const [W, H] = data.viewport;
    const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: scale });
    await page.setContent(html, { waitUntil: 'networkidle' });
    await page.evaluate(async () => {
      const specs = ['500 14px "Inconsolata"','700 14px "Inconsolata"','400 14px "Roboto Mono"','500 14px "Montserrat"','600 14px "Montserrat"','700 14px "Montserrat"','900 14px "Montserrat"',
        '400 14px "Source Sans 3"','600 14px "Source Sans 3"','700 14px "Source Sans 3"','400 14px "Inter"','500 14px "Inter"','700 14px "Inter"','400 14px "Ubuntu"',
        '400 14px "Roboto"','400 14px "Roboto Condensed"','600 14px "Nunito"','500 14px "Oswald"','400 14px "Oswald"','600 14px "Jura"','400 14px "Michroma"','400 14px "Arimo"','700 14px "Arimo"','600 14px "Titillium Web"'];
      await Promise.all(specs.map(s => document.fonts.load(s).catch(() => null)));
      await document.fonts.ready;
    });
    await page.evaluate((d) => window.draw(d), data);
    const target = scale > 1 ? path.join(SHOTS, name + '.png') : path.join(OUT, name + '.png');
    let clip;
    if (args.includes('--crop') && W >= 1000) {
      // crop to the union of the interesting UI parts (+ margin)
      clip = await page.evaluate(() => {
        const names = ['Window', 'Loader', 'Notification', 'DropdownList', 'ColorPanel', 'Popout', 'SearchResults', 'ContextMenu'];
        let r = null;
        document.querySelectorAll('.g').forEach(el => {
          if (!names.includes(el.dataset.name)) return;
          const b = el.getBoundingClientRect();
          if (b.width < 2 || b.height < 2 || b.width >= innerWidth - 1) return;
          r = r ? { l: Math.min(r.l, b.left), t: Math.min(r.t, b.top), r: Math.max(r.r, b.right), b: Math.max(r.b, b.bottom) } : { l: b.left, t: b.top, r: b.right, b: b.bottom };
        });
        if (!r) return null;
        const m = 28;
        const x = Math.max(0, r.l - m), y = Math.max(0, r.t - m);
        return { x, y, width: Math.min(innerWidth, r.r + m) - x, height: Math.min(innerHeight, r.b + m) - y };
      });
    }
    await page.screenshot({ path: target, clip: clip || undefined });
    await page.close();
    console.log('rendered', path.relative(process.cwd(), target));
  }
  await browser.close();
})();
