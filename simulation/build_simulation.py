from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.formatting.rule import FormulaRule
from openpyxl.comments import Comment

wb = Workbook()
F = 'Arial'
BLUE = Font(name=F, color='0000FF'); BLK = Font(name=F); BOLD = Font(name=F, bold=True)
GREEN = Font(name=F, color='008000'); H1 = Font(name=F, bold=True, size=14)
HDR = Font(name=F, bold=True, color='FFFFFF'); HFILL = PatternFill('solid', fgColor='1F3A68')
YEL = PatternFill('solid', fgColor='FFFF00'); GRAY = PatternFill('solid', fgColor='F2F2F2')
thin = Side(style='thin', color='BFBFBF'); BOX = Border(top=thin, bottom=thin, left=thin, right=thin)
PCT = '0.0%;(0.0%);-'; WON = '#,##0"원";(#,##0"원");-'; NUM = '#,##0;(#,##0);-'

def hdr(ws, row, labels, col=1):
    for i, l in enumerate(labels):
        c = ws.cell(row=row, column=col + i, value=l); c.font = HDR; c.fill = HFILL
        c.alignment = Alignment(horizontal='center', vertical='center', wrap_text=True); c.border = BOX
def put(ws, ref, v, font=BLK, fmt=None, fill=None):
    c = ws[ref]; c.value = v; c.font = font
    if fmt: c.number_format = fmt
    if fill: c.fill = fill
    c.border = BOX
    return c
def widths(ws, d):
    for k, v in d.items(): ws.column_dimensions[k].width = v

# ---------------- 안내 ----------------
ws = wb.active; ws.title = '안내'
rows = [
 ('소개뱅크 후원수당 시뮬레이션 (수정안 v0.1)', H1),
 ('', BLK),
 ('사용법', BOLD),
 ('1. [설정] 시트의 파란 글씨 숫자만 바꾸세요. 나머지는 자동 계산됩니다.', BLK),
 ('2. [조직 시뮬레이션]에서 회사 전체 수당 비율이 35%(법정 한도)를 넘는지 확인합니다. 넘으면 빨간색으로 표시됩니다.', BLK),
 ('3. [개인 수당]은 조직 맨 위 회원("나")이 한 달에 받는 수당 예시입니다.', BLK),
 ('4. [직급 기준]의 파란 숫자로 직급 조건을 바꾸고, 아래 "직급 판정 예시"에 회원 실적을 넣으면 직급이 자동 판정됩니다.', BLK),
 ('5. [12개월]은 1년 동안 회사 매출·수당·이익을 보여 줍니다. 법정 한도 35%는 1년 단위로 적용됩니다.', BLK),
 ('6. [원안 비교]는 처음 제출된 구조(원원 글로벌 이미지·직급 엑셀)의 지급률을 보여 줍니다.', BLK),
 ('', BLK),
 ('색 구분', BOLD),
 ('파란 글씨 = 바꿀 수 있는 입력값 · 검은 글씨 = 계산식 · 초록 글씨 = 다른 시트에서 가져온 값 · 노란 칸 = 핵심 가정', BLK),
 ('', BLK),
 ('주의', BOLD),
 ('· 이 표는 사업 설계용 추정입니다. 법률 자문이 아니며, 35% 산정 기준(부가세 포함 여부, 비회원 매출 포함 여부 등)은 변호사 확인이 필요합니다.', BLK),
 ('· 조직은 "모든 회원이 같은 수의 하위 회원을 둔다"는 단순 가정입니다. 실제 조직은 훨씬 불균형합니다.', BLK),
 ('· 직급 공유 수당과 달성 보너스는 예산 전액이 지급된다고 가정했습니다(가장 보수적인 경우).', BLK),
 ('· 모든 수당은 구매 확정된 상품 매출(PV)에서만 발생합니다. 가입·충전만으로는 수당이 생기지 않습니다.', BLK),
]
for i, (t, f) in enumerate(rows, 1):
    c = ws.cell(row=i, column=1, value=t); c.font = f
ws.column_dimensions['A'].width = 130

# ---------------- 설정 ----------------
s = wb.create_sheet('설정')
put(s, 'A1', '설정 (파란 글씨만 수정)', H1); s['A1'].border = Border()
hdr(s, 3, ['항목', '값', '설명'])
items = [
 (4, '조직 가정', None, None, None),
 (5, '1인당 직추천 수(평균)', 2, NUM, '모든 회원이 이 수만큼 하위 회원을 둔다고 가정'),
 (6, '시뮬레이션 대수', 12, NUM, '맨 위 "나"부터 몇 대 아래까지 조직이 있는지 (최대 20)'),
 (7, '활동률', 0.6, PCT, '그 달에 실제로 구매한 회원 비율'),
 (8, '활동 회원 1인 월 구매 PV', 100000, NUM, '구매 확정 기준'),
 (9, 'PV 1점당 원화', 1, NUM, '1 PV = 1원 가정'),
 (10, '수당 규정 (수정안)', None, None, None),
 (11, '추천 수당률', 0.10, PCT, '직추천 판매원 구매 PV의 %'),
 (12, '롤업 시작 대', 2, NUM, '몇 대부터 롤업을 받는지'),
 (13, '롤업 끝 대', 11, NUM, '몇 대까지 롤업을 받는지'),
 (14, '롤업 대별 비율', 0.01, PCT, '각 대마다 %'),
 (15, '직급 공유 수당률', 0.07, PCT, '회사 전체 PV의 %를 6등급 이상에게 지분대로 나눔'),
 (16, '달성 보너스 예산률', 0.03, PCT, '회사 전체 PV의 % 이내에서 직급 첫 달성 시 지급'),
 (17, '공유·보너스 실제 지급률', 1.0, PCT, '예산 중 실제로 지급되는 비율 (100% = 가장 보수적)'),
 (18, '법·경영 기준', None, None, None),
 (19, '법정 한도 (후원수당 총액)', 0.35, PCT, '방문판매법: 1년 단위, 판매원에게 공급한 재화 가격 합계의 35% (원문 확인 필요)'),
 (20, '경고선', 0.30, PCT, '이 비율을 넘으면 노란색 경고'),
 (21, '상품 원가율', 0.45, PCT, '매출 대비 상품 원가 (가정, 실제 값으로 수정)'),
 (22, '결제·공제·물류 비용률', 0.08, PCT, 'PG 수수료, 공제조합, 배송 등 (가정)'),
 (23, '운영비율', 0.10, PCT, '인건비·서버·마케팅 등 (가정)'),
 (24, '사업소득 원천징수율', 0.033, PCT, '수당 지급 시 원천징수 (세율 확인 필요)'),
 (25, '월 활동 회원 증가율', 0.05, PCT, '[12개월] 시트용'),
]
for r, label, v, fmt, desc in items:
    if v is None:
        c = s.cell(row=r, column=1, value=label); c.font = BOLD; c.fill = GRAY
        for col in (2, 3): s.cell(row=r, column=col).fill = GRAY
        continue
    put(s, f'A{r}', label); put(s, f'B{r}', v, BLUE, fmt); put(s, f'C{r}', desc)
for r in (5, 7, 8, 21):
    s[f'B{r}'].fill = YEL
put(s, 'A27', '구조상 최대 지급률', BOLD)
put(s, 'B27', '=B11+(B13-B12+1)*B14+B15+B16', BOLD, PCT)
put(s, 'C27', '모든 수당이 최대로 나가는 경우. 이 값이 35% 이하면 어떤 조직에서도 한도를 넘지 않음')
put(s, 'A28', '판정', BOLD)
put(s, 'B28', '=IF(B27>B19,"❌ 한도 초과",IF(B27>B20,"⚠ 경고","✅ 정상"))', BOLD)
s['C5'].comment = Comment('값 출처: 시뮬레이션 가정 (대표와 협의해 수정)', 'Claude')
widths(s, {'A': 30, 'B': 16, 'C': 80})

# ---------------- 조직 시뮬레이션 ----------------
o = wb.create_sheet('조직 시뮬레이션')
put(o, 'A1', '조직 시뮬레이션 (월 기준, 맨 위 "나" = 0대)', H1); o['A1'].border = Border()
hdr(o, 3, ['대', '회원 수', '활동 회원', '구매 PV', '매출(원)', '추천 수당(원)', '롤업 받는 상위 대수', '롤업 수당(원)', '수당 소계(원)'])
r0 = 4
for i in range(21):
    r = r0 + i
    put(o, f'A{r}', i, BLUE if False else BLK, NUM)
    put(o, f'B{r}', f'=IF(A{r}<=설정!$B$6,설정!$B$5^A{r},0)', BLK, NUM)
    put(o, f'C{r}', f'=B{r}*설정!$B$7', BLK, NUM)
    put(o, f'D{r}', f'=C{r}*설정!$B$8', BLK, NUM)
    put(o, f'E{r}', f'=D{r}*설정!$B$9', BLK, WON)
    put(o, f'F{r}', f'=IF(A{r}>=1,E{r}*설정!$B$11,0)', BLK, WON)
    put(o, f'G{r}', f'=IF(A{r}>=설정!$B$12,MIN(A{r},설정!$B$13)-설정!$B$12+1,0)', BLK, NUM)
    put(o, f'H{r}', f'=E{r}*G{r}*설정!$B$14', BLK, WON)
    put(o, f'I{r}', f'=F{r}+H{r}', BLK, WON)
rl = r0 + 20; t = rl + 1
put(o, f'A{t}', '합계', BOLD)
for col in 'BCDEFHI':
    put(o, f'{col}{t}', f'=SUM({col}{r0}:{col}{rl})', BOLD, WON if col in 'EFHI' else NUM)
o[f'G{t}'].border = BOX
s0 = t + 2
put(o, f'A{s0}', '회사 전체 수당', BOLD); o.merge_cells(f'A{s0}:C{s0}')
hdr(o, s0 + 1, ['구분', '', '', '금액(원)', '매출 대비'])
lines = [
 ('추천 수당', f'=F{t}'),
 ('롤업 수당', f'=H{t}'),
 ('직급 공유 수당', f'=E{t}*설정!$B$15*설정!$B$17'),
 ('달성 보너스', f'=E{t}*설정!$B$16*설정!$B$17'),
]
rr = s0 + 2
for label, f in lines:
    put(o, f'A{rr}', label); put(o, f'D{rr}', f, BLK, WON); put(o, f'E{rr}', f'=IF($E${t}=0,0,D{rr}/$E${t})', BLK, PCT); rr += 1
tot = rr
put(o, f'A{tot}', '수당 합계', BOLD); put(o, f'D{tot}', f'=SUM(D{s0+2}:D{tot-1})', BOLD, WON)
put(o, f'E{tot}', f'=IF($E${t}=0,0,D{tot}/$E${t})', BOLD, PCT); o[f'E{tot}'].fill = YEL
put(o, f'A{tot+1}', '법정 한도', BOLD); put(o, f'E{tot+1}', '=설정!B19', GREEN, PCT)
put(o, f'A{tot+2}', '판정', BOLD)
put(o, f'E{tot+2}', f'=IF(E{tot}>E{tot+1},"❌ 한도 초과",IF(E{tot}>설정!B20,"⚠ 경고","✅ 정상"))', BOLD)
red = PatternFill('solid', fgColor='FF9999'); yel = PatternFill('solid', fgColor='FFE699'); grn = PatternFill('solid', fgColor='C6EFCE')
for ref in (f'E{tot}', f'E{tot+2}'):
    o.conditional_formatting.add(ref, FormulaRule(formula=[f'$E${tot}>설정!$B$19'], fill=red))
    o.conditional_formatting.add(ref, FormulaRule(formula=[f'$E${tot}>설정!$B$20'], fill=yel))
    o.conditional_formatting.add(ref, FormulaRule(formula=[f'$E${tot}<=설정!$B$20'], fill=grn))
put(o, f'A{tot+4}', '회사 손익 (월)', BOLD)
pl = [('매출', f'=E{t}'), ('상품 원가', f'=-E{t}*설정!B21'), ('결제·공제·물류', f'=-E{t}*설정!B22'),
      ('후원수당', f'=-D{tot}'), ('운영비', f'=-E{t}*설정!B23')]
pr = tot + 5
for label, f in pl:
    put(o, f'A{pr}', label); put(o, f'D{pr}', f, BLK, WON); put(o, f'E{pr}', f'=IF($E${t}=0,0,D{pr}/$E${t})', BLK, PCT); pr += 1
put(o, f'A{pr}', '회사 이익', BOLD); put(o, f'D{pr}', f'=SUM(D{tot+5}:D{pr-1})', BOLD, WON); put(o, f'E{pr}', f'=IF($E${t}=0,0,D{pr}/$E${t})', BOLD, PCT)
o.conditional_formatting.add(f'D{pr}:E{pr}', FormulaRule(formula=[f'$D${pr}<0'], fill=red))
ORG_T, ORG_TOT, ORG_PROFIT = t, tot, pr
widths(o, {'A': 16, 'B': 14, 'C': 14, 'D': 18, 'E': 18, 'F': 18, 'G': 14, 'H': 18, 'I': 18})
o.freeze_panes = 'A4'

# ---------------- 개인 수당 ----------------
p = wb.create_sheet('개인 수당')
put(p, 'A1', '개인 수당 예시: 조직 맨 위 회원 "나"의 한 달 수당', H1); p['A1'].border = Border()
hdr(p, 3, ['항목', '값', '설명'])
pi = [
 (4, '내 하위 회원 수', f"=SUM('조직 시뮬레이션'!B5:B24)", GREEN, NUM, '1대 이하 전체'),
 (5, '1대(직추천) 매출', f"='조직 시뮬레이션'!E5", GREEN, WON, ''),
 (6, '추천 수당', '=B5*설정!B11', BLK, WON, '1대 매출 × 추천 수당률'),
 (7, '롤업 대상 매출 합계', f"=SUMPRODUCT(('조직 시뮬레이션'!A4:A24>=설정!B12)*('조직 시뮬레이션'!A4:A24<=설정!B13)*'조직 시뮬레이션'!E4:E24)", BLK, WON, '롤업 시작~끝 대 매출 합계'),
 (8, '롤업 수당', '=B7*설정!B14', BLK, WON, ''),
 (9, '내 공유 지분', 50, BLUE, NUM, '직급 기준의 지분 (예: 10등급 50)'),
 (10, '회사 전체 공유 지분 합계', 500, BLUE, NUM, '6등급 이상 전원의 지분 합 (가정)'),
 (11, '직급 공유 수당', f"=IF(B10=0,0,'조직 시뮬레이션'!D{ORG_TOT-2}*B9/B10)", BLK, WON, '공유 예산 × 내 지분 ÷ 전체 지분'),
 (12, '이번 달 달성 보너스', 0, BLUE, WON, '이번 달 새 직급 달성 시 입력'),
 (13, '수당 합계(세전)', '=B6+B8+B11+B12', BOLD, WON, ''),
 (14, '원천징수', '=-B13*설정!B24', BLK, WON, ''),
 (15, '실수령액', '=B13+B14', BOLD, WON, ''),
 (17, '평균 비교', None, BOLD, None, ''),
 (18, '활동 회원 1인당 평균 수당', f"=IF('조직 시뮬레이션'!C{ORG_T}=0,0,'조직 시뮬레이션'!D{ORG_TOT}/'조직 시뮬레이션'!C{ORG_T})", BLK, WON, '회사 전체 수당 ÷ 활동 회원 수'),
 (19, '활동 회원 1인당 평균 구매액', '=설정!B8*설정!B9', GREEN, WON, ''),
]
for r, label, v, font, fmt, desc in pi:
    put(p, f'A{r}', label, BOLD if font is BOLD else BLK)
    if v is not None: put(p, f'B{r}', v, font, fmt)
    put(p, f'C{r}', desc)
p['B9'].fill = YEL; p['B10'].fill = YEL
put(p, 'A21', '※ "나"는 조직 맨 위라 가장 많이 받는 경우입니다. 대부분의 회원은 평균(18행)에 가깝거나 그보다 적게 받습니다. 홍보에 "나"의 금액만 쓰면 과장 광고가 될 수 있습니다.')
p['A21'].border = Border()
widths(p, {'A': 28, 'B': 20, 'C': 50})

# ---------------- 직급 기준 ----------------
g = wb.create_sheet('직급 기준')
put(g, 'A1', '직급 기준 (수정안, 파란 글씨 수정 가능)', H1); g['A1'].border = Border()
hdr(g, 3, ['등급', '이름', '본인 누적 PV', '직추천 활동 판매원(명)', '그룹 월 PV', '최소 계열 수', '계열별 최소 비중', '롤업 개방 끝 대', '공유 지분'])
grades = [
 ('판매원', '판매원', 0, 0, 0, 0, 0, 1, 0),
 ('1등급', '일반', 300, 2, 0, 0, 0, 6, 0),
 ('2등급', '일반', 300, 2, 1000, 0, 0, 6, 0),
 ('3등급', '일반', 300, 2, 3000, 0, 0, 11, 0),
 ('4등급', '일반', 300, 2, 10000, 0, 0, 11, 0),
 ('5등급', '일반', 300, 2, 30000, 0, 0, 11, 0),
 ('6등급', '가맹점', 300, 3, 100000, 3, 0.2, 11, 30),
 ('7등급', '대리점', 300, 3, 300000, 3, 0.2, 11, 35),
 ('8등급', '지사', 300, 3, 1000000, 3, 0.2, 11, 40),
 ('9등급', '본부', 300, 3, 3000000, 3, 0.2, 11, 45),
 ('10등급', '총괄본부', 300, 3, 10000000, 3, 0.2, 11, 50),
]
for i, row in enumerate(grades):
    r = 4 + i
    for j, v in enumerate(row):
        col = 'ABCDEFGHI'[j]
        fmt = PCT if col == 'G' else (NUM if j >= 2 else None)
        put(g, f'{col}{r}', v, BLUE if j >= 1 else BOLD, fmt)
gl = 4 + len(grades) - 1
put(g, f'A{gl+2}', '※ 조건은 인원 수가 아니라 구매 확정 매출(PV) 기준입니다. "직추천 활동 판매원"은 그 달 실제 구매한 직추천만 셉니다. 1~2등급은 롤업 2~6대, 3등급부터 2~11대를 받습니다.')
g[f'A{gl+2}'].border = Border()
q = gl + 4
put(g, f'A{q}', '직급 판정 예시 (회원 실적을 파란 칸에 입력)', BOLD); g[f'A{q}'].border = Border()
hdr(g, q + 1, ['항목', '값'])
ex = [('본인 누적 PV', 500), ('직추천 활동 판매원(명)', 4), ('그룹 월 PV', 150000), ('계열 수(20% 이상 차지하는 계열)', 3), ('가장 약한 계열 비중', 0.25)]
for k, (label, v) in enumerate(ex):
    r = q + 2 + k
    put(g, f'A{r}', label); put(g, f'B{r}', v, BLUE, PCT if 'G' == '' or label.startswith('가장') else NUM); g[f'B{r}'].fill = YEL
e1, e2, e3, e4, e5 = [f'$B${q+2+k}' for k in range(5)]
# 충족 여부 helper (J열)
put(g, 'J3', '판정용(자동)', HDR); g['J3'].fill = HFILL
for i in range(len(grades)):
    r = 4 + i
    put(g, f'J{r}', f'=IF(AND({e1}>=C{r},{e2}>=D{r},{e3}>=E{r},{e4}>=F{r},{e5}>=G{r}),ROW()-3,0)', BLK, NUM)
rq = q + 2 + len(ex)
put(g, f'A{rq}', '판정 직급', BOLD)
put(g, f'B{rq}', f'=INDEX(A4:A{gl},MAX(J4:J{gl}))&" ("&INDEX(B4:B{gl},MAX(J4:J{gl}))&")"', BOLD); g[f'B{rq}'].fill = GRAY
widths(g, {'A': 30, 'B': 18, 'C': 14, 'D': 16, 'E': 16, 'F': 12, 'G': 14, 'H': 14, 'I': 12, 'J': 12})

# ---------------- 12개월 ----------------
m = wb.create_sheet('12개월')
put(m, 'A1', '12개월 시뮬레이션 (법정 한도는 1년 단위)', H1); m['A1'].border = Border()
hdr(m, 3, ['월', '활동 회원', '매출(원)', '후원수당(원)', '상품 원가', '결제·공제·물류', '운영비', '회사 이익', '누적 매출', '누적 수당', '누적 수당 비율'])
ratio = f"'조직 시뮬레이션'!$E${ORG_TOT}"
for i in range(12):
    r = 4 + i
    put(m, f'A{r}', f'{i+1}월')
    put(m, f'B{r}', f"='조직 시뮬레이션'!C{ORG_T}" if i == 0 else f'=B{r-1}*(1+설정!$B$25)', GREEN if i == 0 else BLK, NUM)
    put(m, f'C{r}', f'=B{r}*설정!$B$8*설정!$B$9', BLK, WON)
    put(m, f'D{r}', f'=C{r}*{ratio}', BLK, WON)
    put(m, f'E{r}', f'=C{r}*설정!$B$21', BLK, WON)
    put(m, f'F{r}', f'=C{r}*설정!$B$22', BLK, WON)
    put(m, f'G{r}', f'=C{r}*설정!$B$23', BLK, WON)
    put(m, f'H{r}', f'=C{r}-D{r}-E{r}-F{r}-G{r}', BLK, WON)
    put(m, f'I{r}', f'=SUM($C$4:C{r})', BLK, WON)
    put(m, f'J{r}', f'=SUM($D$4:D{r})', BLK, WON)
    put(m, f'K{r}', f'=IF(I{r}=0,0,J{r}/I{r})', BLK, PCT)
put(m, 'A16', '연간 합계', BOLD)
for col in 'CDEFGH':
    put(m, f'{col}16', f'=SUM({col}4:{col}15)', BOLD, WON)
put(m, 'K16', '=IF(C16=0,0,D16/C16)', BOLD, PCT); m['K16'].fill = YEL
put(m, 'A17', '판정', BOLD); put(m, 'K17', '=IF(K16>설정!B19,"❌ 한도 초과",IF(K16>설정!B20,"⚠ 경고","✅ 정상"))', BOLD)
for ref in ('K16', 'K17'):
    m.conditional_formatting.add(ref, FormulaRule(formula=['$K$16>설정!$B$19'], fill=red))
    m.conditional_formatting.add(ref, FormulaRule(formula=['$K$16>설정!$B$20'], fill=yel))
    m.conditional_formatting.add(ref, FormulaRule(formula=['$K$16<=설정!$B$20'], fill=grn))
m.conditional_formatting.add('H4:H16', FormulaRule(formula=['H4<0'], fill=red))
widths(m, {c: 16 for c in 'ABCDEFGHIJK'})

# ---------------- 원안 비교 ----------------
w = wb.create_sheet('원안 비교')
put(w, 'A1', '원안(제출 자료) 지급률 비교', H1); w['A1'].border = Border()
put(w, 'A3', '판매 1건 금액(원)'); put(w, 'B3', 450000, BLUE, WON); w['B3'].fill = YEL
put(w, 'C3', '출처: 원원 글로벌 이미지 $300(45만 원), 대표 제출 자료')
put(w, 'A4', '달러 환율(원)'); put(w, 'B4', 1500, BLUE, NUM); put(w, 'C4', '이미지 기준 $300=45만 원 → 1,500원')
hdr(w, 6, ['수당', '원안 비율', '1건당 금액(원)', '수정안 비율', '근거'])
lvb = '(60+60+93.7+194.4+587.7)/((2+4+8+16+32)*300)'
ol = [
 ('쇼핑몰 추천수당 1대', 0.10, '=설정!B11', '이미지'),
 ('마케팅 추천수당', 0.10, 0, '이미지 (수정안: 추천 수당으로 통합)'),
 ('롤업 수당', 0.20, '=(설정!B13-설정!B12+1)*설정!B14', '이미지: 1~20대 각 1% / 수정안: 2~11대 각 1%'),
 ('단계보너스', f'={lvb}', '=설정!B16', '이미지 1~5대 $ 금액 ÷ 해당 대 매출(추정) / 수정안: 달성 보너스'),
 ('추천인 판매액의 50%', 0.50, 0, '엑셀 1~5등급 (수정안: 삭제)'),
 ('산하 매출 20% (1/n)', 0.20, '=설정!B15', '엑셀 6등급 이상 / 수정안: 직급 공유 7%'),
]
for k, (label, a, b, src) in enumerate(ol):
    r = 7 + k
    put(w, f'A{r}', label); put(w, f'B{r}', a, BLUE, PCT); put(w, f'C{r}', f'=$B$3*B{r}', BLK, WON)
    put(w, f'D{r}', b, GREEN if isinstance(b, str) else BLUE, PCT); put(w, f'E{r}', src)
put(w, 'A13', '이미지 기준 합계', BOLD); put(w, 'B13', '=SUM(B7:B10)', BOLD, PCT); put(w, 'C13', '=$B$3*B13', BOLD, WON)
put(w, 'A14', '엑셀 포함 합계', BOLD); put(w, 'B14', '=SUM(B7:B12)', BOLD, PCT); put(w, 'C14', '=$B$3*B14', BOLD, WON)
put(w, 'D14', '=SUM(D7:D12)', BOLD, PCT); put(w, 'E14', '← 수정안 구조상 최대')
put(w, 'A15', '법정 한도', BOLD); put(w, 'B15', '=설정!B19', GREEN, PCT); put(w, 'D15', '=설정!B19', GREEN, PCT)
for ref in ('B13', 'B14', 'D14'):
    w.conditional_formatting.add(ref, FormulaRule(formula=[f'{ref}>설정!$B$19'], fill=red))
    w.conditional_formatting.add(ref, FormulaRule(formula=[f'{ref}<=설정!$B$19'], fill=grn))
put(w, 'A17', '원안 등급 조건: 필요한 하위 인원', BOLD); w['A17'].border = Border()
hdr(w, 18, ['등급', '해당 대 인원(2배씩)', '누적 하위 인원'])
for k in range(1, 21):
    r = 18 + k
    put(w, f'A{r}', f'{k}등급'); put(w, f'B{r}', f'=2^{k}', BLK, NUM); put(w, f'C{r}', f'=SUM($B$19:B{r})', BLK, NUM)
put(w, 'A40', '※ 20등급은 하위 약 210만 명이 필요합니다. 인원 기준 등급은 모집 보상으로 해석될 위험이 큽니다.'); w['A40'].border = Border()
widths(w, {'A': 26, 'B': 18, 'C': 18, 'D': 14, 'E': 60})

for sh in wb.worksheets:
    sh.sheet_view.showGridLines = False if sh.title == '안내' else True
wb.save(__import__('os').path.join(__import__('os').path.dirname(__import__('os').path.abspath(__file__)), 'sogaebank_bonus_simulation.xlsx'))
print('saved', ORG_T, ORG_TOT, ORG_PROFIT)
