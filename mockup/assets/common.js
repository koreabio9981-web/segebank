/* 소개뱅크 시안 공통 스크립트: 샘플 데이터, 시안용 저장소, 화면 도우미 */

/* ===== 샘플 데이터 ===== */
const SEED = {
  categories: ['식품', '건강', '생활', '뷰티', '가전'],
  members: [
    {id:'kim01',name:'김민수',grade:'골드',sponsor:'root',status:'정상',joined:'2026-03-02',sales:4200000,pv:6200000},
    {id:'lee22',name:'이서연',grade:'실버',sponsor:'kim01',status:'정상',joined:'2026-05-11',sales:1850000,pv:1450000},
    {id:'park7',name:'박준호',grade:'판매원',sponsor:'kim01',status:'정상',joined:'2026-07-20',sales:620000,pv:380000},
    {id:'yoon4',name:'윤지아',grade:'실버',sponsor:'kim01',status:'정상',joined:'2026-06-08',sales:1420000,pv:1200000},
    {id:'choi3',name:'최유진',grade:'실버',sponsor:'lee22',status:'정지',joined:'2026-08-03',sales:1100000,pv:1050000},
    {id:'jung5',name:'정하늘',grade:'판매원',sponsor:'lee22',status:'정상',joined:'2026-10-15',sales:330000,pv:210000},
    {id:'han9',name:'한도윤',grade:'판매원',sponsor:'park7',status:'정상',joined:'2026-11-01',sales:150000,pv:105000},
    {id:'seo8',name:'서예준',grade:'판매원',sponsor:'yoon4',status:'정상',joined:'2026-09-12',sales:280000,pv:196000},
    {id:'kang2',name:'강민재',grade:'판매원',sponsor:'yoon4',status:'정상',joined:'2026-10-27',sales:330000,pv:231000},
  ],
  sellers: [
    {id:'S001',user:'greenfood',company:'그린푸드',ceo:'오정민',bizNo:'123-45-67890',phone:'02-111-2222',email:'green@example.com',cat:'식품',status:'승인',applied:'2026-09-01',decided:'2026-09-02',reason:''},
    {id:'S002',user:'healthplus',company:'헬스플러스',ceo:'문지호',bizNo:'234-56-78901',phone:'031-222-3333',email:'hp@example.com',cat:'건강',status:'승인',applied:'2026-09-15',decided:'2026-09-16',reason:''},
    {id:'S003',user:'cleanlife',company:'클린라이프',ceo:'배수아',bizNo:'345-67-89012',phone:'02-333-4444',email:'clean@example.com',cat:'생활',status:'승인대기',applied:'2026-11-25',decided:'',reason:''},
    {id:'S004',user:'beautyday',company:'뷰티데이',ceo:'신하린',bizNo:'456-78-90123',phone:'02-444-5555',email:'bd@example.com',cat:'뷰티',status:'승인대기',applied:'2026-11-26',decided:'',reason:''},
    {id:'S005',user:'fastmall',company:'패스트몰',ceo:'구태오',bizNo:'567-89-01234',phone:'02-555-6666',email:'fm@example.com',cat:'가전',status:'반려',applied:'2026-11-10',decided:'2026-11-11',reason:'통신판매업 신고증 누락'},
  ],
  products: [
    {no:101,seller:'S001',name:'유기농 배추김치 2kg',cat:'식품',price:24900,list:29000,stock:120,pv:20,status:'판매중',color:'#d9534f'},
    {no:102,seller:'S001',name:'유기농 배추김치 5kg',cat:'식품',price:58900,list:65000,stock:80,pv:50,status:'판매중',color:'#c0392b'},
    {no:103,seller:'S001',name:'국산 양갈비 패밀리 세트',cat:'식품',price:79800,list:89000,stock:0,pv:70,status:'품절',color:'#8e5b3c'},
    {no:201,seller:'S002',name:'발 마사지기 프리미엄',cat:'건강',price:990000,list:1200000,stock:15,pv:900,status:'판매중',color:'#34495e'},
    {no:202,seller:'S002',name:'꿀 스틱 30포 2세트',cat:'건강',price:44000,list:52000,stock:200,pv:40,status:'판매중',color:'#e0a800'},
    {no:203,seller:'S002',name:'천일염 300시간 숙성 60포',cat:'건강',price:147000,list:150000,stock:60,pv:130,status:'판매중',color:'#2e86c1'},
    {no:204,seller:'S002',name:'수면 안대',cat:'생활',price:19900,list:25000,stock:300,pv:15,status:'숨김',color:'#5d6d7e'},
    {no:205,seller:'S002',name:'미네랄 워터 500ml 30병',cat:'식품',price:55000,list:85000,stock:40,pv:45,status:'판매중',color:'#48c9b0'},
  ],
  orders: [
    {no:'O-26112601',buyer:'kim01',items:[[201,1]],date:'2026-11-26',st:'결제완료',track:''},
    {no:'O-26112502',buyer:'lee22',items:[[101,2],[202,1]],date:'2026-11-25',st:'배송준비',track:''},
    {no:'O-26112003',buyer:'park7',items:[[203,1]],date:'2026-11-20',st:'배송중',track:'CJ 6012-3456-7890'},
    {no:'O-26111504',buyer:'kim01',items:[[102,1]],date:'2026-11-15',st:'배송완료',track:'CJ 6012-1111-2222'},
    {no:'O-26111005',buyer:'yoon4',items:[[205,2]],date:'2026-11-10',st:'구매확정',track:'한진 5100-2233'},
  ],
  bonuses: [
    {date:'2026-11-17~23',type:'직추천 수당',from:'lee22',amt:85000,st:'지급완료'},
    {date:'2026-11-17~23',type:'바이너리 매칭',from:'소실적 1,240,000 PV',amt:62000,st:'지급완료'},
    {date:'2026-10월',type:'롤업 수당',from:'1~7대',amt:118000,st:'지급완료'},
    {date:'2026-10월',type:'직급 보너스',from:'골드 지분 1',amt:7200,st:'지급완료'},
    {date:'2026-11-24~30',type:'직추천 수당',from:'yoon4',amt:61000,st:'정산예정'},
    {date:'2026-11-24~30',type:'바이너리 매칭',from:'소실적 880,000 PV',amt:44000,st:'정산예정'},
  ],
  withdrawals: [
    {no:'P-2026-1202',who:'kim01',amt:105000,fee:3460,bank:'국민 ***-7890',date:'2026-12-02',st:'지급예정'},
    {no:'P-2026-1125',who:'kim01',amt:147000,fee:4850,bank:'국민 ***-7890',date:'2026-11-25',st:'지급완료'},
    {no:'P-2026-1125',who:'lee22',amt:150000,fee:4950,bank:'신한 ***-1234',date:'2026-11-25',st:'지급완료'},
    {no:'P-2026-1125',who:'park7',amt:8000,fee:0,bank:'농협 ***-5555',date:'2026-11-25',st:'이월'},
    {no:'P-2026-1125',who:'jung5',amt:42000,fee:1380,bank:'-',date:'2026-11-25',st:'보류'},
  ],
  settlements: [
    {period:'2026-11 1차 (11/01~11/15)',seller:'S001',gross:1450000,rate:12,st:'지급완료'},
    {period:'2026-11 1차 (11/01~11/15)',seller:'S002',gross:3980000,rate:12,st:'지급완료'},
    {period:'2026-11 2차 (11/16~11/30)',seller:'S001',gross:620000,rate:12,st:'정산예정'},
    {period:'2026-11 2차 (11/16~11/30)',seller:'S002',gross:2210000,rate:12,st:'정산예정'},
  ],
  notices: [
    {t:'12월 정산 일정 안내',d:'2026-11-25',to:'전체',body:'12월 회원 수당은 매주 화요일, 판매자 정산은 월 2회 진행됩니다.'},
    {t:'판매자 일괄 등록 양식 변경',d:'2026-11-20',to:'판매자',body:'일괄 등록 양식에 "배송비" 열이 추가되었습니다. 새 양식을 내려받아 사용해 주세요.'},
    {t:'개인정보 처리방침 변경',d:'2026-11-01',to:'전체',body:'변경된 방침은 12월 1일부터 적용됩니다.'},
  ],
  inquiries: [
    {t:'출금 처리 기간 문의',who:'lee22',to:'관리자',d:'2026-11-25',st:'답변대기',a:''},
    {t:'김치 배송일 문의',who:'park7',to:'S001',d:'2026-11-24',st:'답변대기',a:''},
    {t:'배송지 변경 요청',who:'kim01',to:'S002',d:'2026-11-21',st:'답변완료',a:'변경 처리했습니다.'},
  ],
};

/* PV = 공급가(판매가 ÷ 1.1, 부가세 제외) × 70% (기준서 v0.3 제2조, 시스템 자동 계산) */
SEED.products.forEach(p => p.pv = Math.floor(p.price / 1.1 * 0.7));

/* ===== 시안용 저장소 =====
   판매자 신청 → 관리자 승인 흐름을 화면끼리 이어서 보여 주려고 브라우저 저장소(localStorage)를 씁니다.
   실제 서비스에서는 서버 DB가 이 역할을 합니다. */
const KEY = 'segebank-mock-v2';
const DB = (() => {
  let data;
  try { data = JSON.parse(localStorage.getItem(KEY)); } catch (e) { data = null; }
  if (!data) data = JSON.parse(JSON.stringify(SEED));
  return data;
})();
function save(){ try { localStorage.setItem(KEY, JSON.stringify(DB)); } catch (e) {} }
function resetDemo(){ try { localStorage.removeItem(KEY); } catch (e) {} location.reload(); }

/* ===== 도우미 ===== */
const won = n => Number(n).toLocaleString('ko-KR') + '원';
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const today = () => new Date().toISOString().slice(0, 10);
const productBy = no => DB.products.find(p => p.no === no);
const sellerBy = id => DB.sellers.find(s => s.id === id);
const orderTotal = o => o.items.reduce((s, [no, q]) => s + (productBy(no)?.price || 0) * q, 0);
const orderTitle = o => { const p = productBy(o.items[0][0]); return (p ? p.name : '상품') + (o.items.length > 1 ? ` 외 ${o.items.length - 1}건` : ''); };

const BADGE = {
  정상:'ok',지급완료:'ok',승인:'ok',배송완료:'ok',구매확정:'ok',답변완료:'ok',판매중:'ok',
  대기:'warn',승인대기:'warn',정산예정:'warn',지급예정:'warn',이월:'g',보류:'bad',답변대기:'warn',배송준비:'warn',
  결제완료:'n',배송중:'n',
  정지:'bad',반려:'bad',품절:'bad',판매중지:'bad',오류:'bad',
  숨김:'g',취소:'g',
};
const badge = s => `<span class="b ${BADGE[s] || 'n'}">${esc(s)}</span>`;
const table = (cols, rows, emptyMsg = '내역이 없습니다') => !rows.length ? `<div class="empty">${emptyMsg}</div>` :
  `<div class="tbl"><table><thead><tr>${cols.map(c => `<th class="${c[2] || ''}">${c[0]}</th>`).join('')}</tr></thead>
  <tbody>${rows.map((r, i) => `<tr class="${r._err ? 'err' : ''}">${cols.map(c => `<td class="${c[2] || ''}">${c[1](r, i)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
const kpis = arr => `<div class="grid">${arr.map(([l, v]) => `<div class="card kpi"><div class="l">${l}</div><div class="v">${v}</div></div>`).join('')}</div>`;
const card = (h, body) => `<div class="card">${h ? `<h3>${h}</h3>` : ''}${body}</div>`;
const thumb = (p, cls = '') => `<div class="thumb ${cls}" style="background:${p.color || '#8a96a8'}">${esc(p.name[0])}</div>`;
const periodBar = (extra = '') => `<div class="bar"><input type="date" value="2026-11-01"><input type="date" value="${today()}">${extra}<button>조회</button></div>`;

function toast(msg){
  let t = document.getElementById('toast');
  if (!t) { t = document.createElement('div'); t.id = 'toast'; t.className = 'toast'; document.body.appendChild(t); }
  t.textContent = msg; t.style.display = 'block';
  clearTimeout(t._h); t._h = setTimeout(() => t.style.display = 'none', 2000);
}

/* 간단한 입력 창: fields = [{name,label,type,value}] → onOk(values) */
function modal(title, fields, onOk, okLabel = '확인'){
  const bg = document.createElement('div'); bg.className = 'modal-bg';
  bg.innerHTML = `<div class="modal"><h3>${title}</h3>${fields.map(f => `<div class="field"><label>${f.label}</label>${
    f.type === 'textarea' ? `<textarea rows="3" name="${f.name}">${esc(f.value || '')}</textarea>` : `<input name="${f.name}" type="${f.type || 'text'}" value="${esc(f.value || '')}">`}</div>`).join('')}
    <div style="display:flex;gap:8px;justify-content:flex-end"><button class="ghost" data-x>취소</button><button data-ok>${okLabel}</button></div></div>`;
  document.body.appendChild(bg);
  bg.querySelector('[data-x]').onclick = () => bg.remove();
  bg.querySelector('[data-ok]').onclick = () => {
    const v = {}; bg.querySelectorAll('[name]').forEach(el => v[el.name] = el.value.trim());
    if (onOk(v) !== false) bg.remove();
  };
  const first = bg.querySelector('[name]'); if (first) first.focus();
}

/* 조직도 */
const nodeHtml = k => `<span class="node g-${k.grade}${k.status === '정지' ? ' stop' : ''}"><b>${esc(k.name)}</b><small>${k.id} · ${k.grade}${k.status === '정지' ? ' · 정지' : ''}</small></span>`;
function tree(root){
  const kids = DB.members.filter(m => m.sponsor === root);
  return kids.length ? `<ul>${kids.map(k => `<li>${nodeHtml(k)}${tree(k.id)}</li>`).join('')}</ul>` : '';
}
const renderTree = id => { const m = DB.members.find(x => x.id === id); return `<ul><li>${nodeHtml(m)}${tree(id)}</li></ul>`; };
function centerTrees(){ document.querySelectorAll('.tree').forEach(t => t.scrollLeft = (t.scrollWidth - t.clientWidth) / 2); }

/* ===== 사이드 메뉴형 앱 (오피스, 판매자센터, 관리자 공통) =====
   cfg = { brand, sub, role, menus: [ ['그룹명', { key: ['제목', 화면함수] }] ], guard?: () => 화면HTML | null } */
function sideApp(cfg){
  document.body.innerHTML = `
    <nav class="side" id="side"></nav>
    <main class="main">
      <div class="top">
        <div style="display:flex;gap:10px;align-items:center"><button class="ghost menu-btn" onclick="side.classList.toggle('open')">☰</button><h1 id="title"></h1></div>
        <div style="display:flex;gap:8px;align-items:center"><span class="mock">시안 · 샘플 데이터</span><button class="ghost sm" onclick="resetDemo()">데모 초기화</button></div>
      </div>
      <div id="view"></div>
    </main>`;
  const flat = {}; cfg.menus.forEach(([, m]) => Object.assign(flat, m));
  function render(){
    const page = location.hash.slice(1).split('/')[0];
    const guard = cfg.guard ? cfg.guard() : null;
    const key = flat[page] ? page : Object.keys(flat)[0];
    const side = document.getElementById('side');
    side.innerHTML = `<div class="logo">소개뱅크 <span>${cfg.brand}</span></div><div class="role">${cfg.role()}</div>`
      + (guard ? '' : cfg.menus.map(([g, m]) => `<div class="grp">${g}</div>` + Object.entries(m).map(([k, [t]]) => `<a href="#${k}" class="${k === key ? 'on' : ''}">${t}</a>`).join('')).join(''))
      + `<a class="home" href="index.html">← 시안 전체 화면 목록</a>`;
    side.classList.remove('open');
    document.getElementById('title').textContent = guard ? guard.title : flat[key][0];
    document.getElementById('view').innerHTML = guard ? guard.html : flat[key][1]();
    centerTrees();
    window.scrollTo(0, 0);
  }
  window.rerender = render;
  window.addEventListener('hashchange', render); render();
}
