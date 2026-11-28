// 브라우저 안에서 실행: 현재 화면 DOM을 편집 가능한 SVG(사각형 + 텍스트)로 변환
window.__dom2svg = function(screenName){
  const W = document.documentElement.scrollWidth;
  const H = Math.max(document.documentElement.scrollHeight, document.body.scrollHeight);
  const ids = {};
  const uid = s => { s = (s||'layer').replace(/[^\w가-힣\-]+/g,'-').replace(/^-+|-+$/g,'').slice(0,40) || 'layer'; ids[s] = (ids[s]||0)+1; return ids[s] > 1 ? `${s}-${ids[s]}` : s; };
  const esc = s => s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  const col = c => { const m = c && c.match(/rgba?\(([^)]+)\)/); if(!m) return null; const p = m[1].split(/[ ,\/]+/).filter(Boolean).map(Number); const a = p.length > 3 ? p[3] : 1; if (a === 0) return null; const hex = '#' + p.slice(0,3).map(v => Math.round(v).toString(16).padStart(2,'0')).join(''); return {hex, a}; };
  const fillAttr = (c, k='fill') => `${k}="${c.hex}"${c.a < 1 ? ` ${k}-opacity="${+c.a.toFixed(3)}"` : ''}`;
  const sy = window.scrollY, sx = window.scrollX;
  const R = r => ({x: +(r.left+sx).toFixed(1), y: +(r.top+sy).toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1)});
  const FONT = `'Noto Sans KR', sans-serif`;
  function textRuns(node, cs){
    const out = []; const t = node.textContent; if (!t.trim()) return out;
    const rng = document.createRange(); let line = null;
    for (let i = 0; i < t.length; i++){
      rng.setStart(node, i); rng.setEnd(node, i+1);
      const rs = rng.getClientRects(); if (!rs.length) continue; const r = rs[rs.length-1];
      if (r.width === 0 && /\s/.test(t[i])) { if (line) line.s += ' '; continue; }
      if (!line || Math.abs(r.top - line.top) > r.height*0.5 || r.left < line.right - 2){
        if (line) out.push(line); line = {s: '', left: r.left, top: r.top, h: r.height, right: r.right};
      }
      line.s += t[i]; line.right = r.right;
    }
    if (line) out.push(line);
    return out.map(l => ({...l, s: l.s.replace(/\s+/g,' ').trim()})).filter(l => l.s);
  }
  function textEl(s, x, top, h, cs, name){
    const c = col(cs.color) || {hex:'#000000', a:1};
    const fs = parseFloat(cs.fontSize); const base = top + h*0.80 + sy;
    const wgt = parseInt(cs.fontWeight) || 400;
    return `<text id="${uid(name || s)}" x="${(x+sx).toFixed(1)}" y="${base.toFixed(1)}" font-family="${FONT}" font-size="${fs}" font-weight="${wgt}" ${fillAttr(c)}${cs.textDecorationLine.includes('line-through') ? ' text-decoration="line-through"' : ''}${cs.textDecorationLine.includes('underline') ? ' text-decoration="underline"' : ''}>${esc(s)}</text>`;
  }
  function box(el, cs, r){
    let o = '';
    const bg = col(cs.backgroundColor);
    const rad = Math.min(parseFloat(cs.borderTopLeftRadius)||0, r.w/2, r.h/2);
    const bw = ['Top','Right','Bottom','Left'].map(s => parseFloat(cs['border'+s+'Width'])||0);
    const bc = ['Top','Right','Bottom','Left'].map(s => cs['border'+s+'Style'] === 'none' ? null : col(cs['border'+s+'Color']));
    const uniform = bw.every(w => w === bw[0]) && bw[0] > 0 && bc.every(c => c && bc[0] && c.hex === bc[0].hex);
    const nm = (el.className && typeof el.className === 'string' ? el.className.split(' ')[0] : el.tagName.toLowerCase());
    if (bg || uniform){
      const st = uniform ? ` ${fillAttr(bc[0],'stroke')} stroke-width="${bw[0]}"${cs.borderTopStyle === 'dashed' ? ` stroke-dasharray="${bw[0]*3} ${bw[0]*2}"` : ''}` : '';
      const ins = uniform ? bw[0]/2 : 0;
      o += `<rect id="${uid(nm+'-bg')}" x="${r.x+ins}" y="${r.y+ins}" width="${Math.max(0,r.w-2*ins)}" height="${Math.max(0,r.h-2*ins)}"${rad ? ` rx="${rad}"` : ''} ${bg ? fillAttr(bg) : 'fill="none"'}${st}/>`;
    }
    if (!uniform){
      const sides = [[r.x, r.y, r.w, bw[0]], [r.x+r.w-bw[1], r.y, bw[1], r.h], [r.x, r.y+r.h-bw[2], r.w, bw[2]], [r.x, r.y, bw[3], r.h]];
      sides.forEach(([x,y,w,h], i) => { if (bw[i] > 0 && bc[i]) o += `<rect id="${uid(nm+'-line')}" x="${x}" y="${y}" width="${w}" height="${h}" ${fillAttr(bc[i])}/>`; });
    }
    return o;
  }
  function walk(el){
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden' || +cs.opacity === 0) return '';
    if (['SCRIPT','STYLE','LINK','META','TITLE','HEAD'].includes(el.tagName)) return '';
    if (!el.getClientRects().length) return '';
    if (el.parentElement && el.parentElement.tagName === 'DETAILS' && !el.parentElement.open && el.tagName !== 'SUMMARY') return '';
    const r = R(el.getBoundingClientRect());
    let o = '';
    if (r.w > 0 && r.h > 0) o += box(el, cs, r);
    const tag = el.tagName;
    if (tag === 'INPUT' && (el.type === 'checkbox' || el.type === 'radio')){
      const c = el.checked ? '#2457d6' : '#ffffff';
      o += el.type === 'radio' ? `<circle id="${uid('radio')}" cx="${r.x+r.w/2}" cy="${r.y+r.h/2}" r="${Math.min(r.w,r.h)/2-1}" fill="${c}" stroke="#8a96a8"/>` : `<rect id="${uid('checkbox')}" x="${r.x+1}" y="${r.y+1}" width="${r.w-2}" height="${r.h-2}" rx="3" fill="${c}" stroke="#8a96a8"/>`;
    } else if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT'){
      const v = tag === 'SELECT' ? (el.options[el.selectedIndex]||{}).text || '' : (el.value || el.placeholder || '');
      if (v && el.type !== 'file' && el.type !== 'hidden'){
        const pl = parseFloat(cs.paddingLeft)||8, fs = parseFloat(cs.fontSize);
        const h = fs*1.45, top = el.getBoundingClientRect().top + (tag === 'TEXTAREA' ? parseFloat(cs.paddingTop) : (r.h - h)/2);
        const fake = {color: el.value || tag === 'SELECT' ? cs.color : 'rgb(154,163,181)', fontSize: cs.fontSize, fontWeight: cs.fontWeight, textDecorationLine: ''};
        o += textEl(v.split('\n')[0], el.getBoundingClientRect().left + pl, top, h, fake, (tag==='SELECT'?'select-':'input-') + v);
        if (tag === 'SELECT') o += `<path id="${uid('chevron')}" d="M${r.x+r.w-18} ${r.y+r.h/2-2} l4 4 l4 -4" fill="none" stroke="#6b7487" stroke-width="1.5"/>`;
      }
    } else {
      for (const n of el.childNodes){
        if (n.nodeType === 3){ textRuns(n, cs).forEach(l => { o += textEl(l.s, l.left, l.top, l.h, cs); }); }
        else if (n.nodeType === 1) o += walk(n);
      }
    }
    if (el.classList && el.classList.contains('tree')){
      let ln = '';
      el.querySelectorAll('li').forEach(li => {
        const pn = li.querySelector(':scope > .node'); const kids = [...li.querySelectorAll(':scope > ul > li > .node')];
        if (!pn || !kids.length) return;
        const a = R(pn.getBoundingClientRect()); const cx = a.x + a.w/2, by = a.y + a.h;
        const ks = kids.map(k => R(k.getBoundingClientRect())); const ty = Math.min(...ks.map(k => k.y)); const my = (by + ty)/2;
        let d = `M${cx} ${by} V${my}`;
        const xs = ks.map(k => k.x + k.w/2);
        if (xs.length > 1) d += ` M${Math.min(...xs)} ${my} H${Math.max(...xs)}`;
        ks.forEach(k => { d += ` M${k.x + k.w/2} ${my} V${k.y}`; });
        ln += `<path id="${uid('connector')}" d="${d}" fill="none" stroke="#b9c4da" stroke-width="1"/>`;
      });
      if (ln) o = `<g id="${uid('tree-lines')}">${ln}</g>` + o;
    }
    if (!o) return '';
    const isLeafText = !o.includes('<g') && !((cs.overflowX !== 'visible' || cs.overflowY !== 'visible') && el !== document.body) && (o.match(/<(rect|text|circle|path)/g)||[]).length === 1;
    if (isLeafText) return o;
    const cls = typeof el.className === 'string' && el.className.trim() ? el.className.trim().split(/\s+/)[0] : '';
    const name = el.id || cls || tag.toLowerCase();
    let clip = '';
    if (el !== document.body && (cs.overflowX !== 'visible' || cs.overflowY !== 'visible') && r.w > 0 && r.h > 0){
      const cid = uid(name + '-clip'); const rad = parseFloat(cs.borderTopLeftRadius)||0;
      o = `<clipPath id="${cid}"><rect x="${r.x}" y="${r.y}" width="${r.w}" height="${r.h}"${rad ? ` rx="${rad}"` : ''}/></clipPath>` + o;
      clip = ` clip-path="url(#${cid})"`;
    }
    return `<g id="${uid(name)}"${clip}${+cs.opacity < 1 ? ` opacity="${cs.opacity}"` : ''}>${o}</g>`;
  }
  const bodyBg = col(getComputedStyle(document.body).backgroundColor) || col(getComputedStyle(document.documentElement).backgroundColor) || {hex:'#ffffff',a:1};
  const inner = [...document.body.children].map(walk).join('');
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}"><g id="${esc(screenName)}"><rect id="background" x="0" y="0" width="${W}" height="${H}" ${fillAttr(bodyBg)}/>${inner}</g></svg>`;
};
