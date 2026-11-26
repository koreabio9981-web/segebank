# 소개뱅크 보상플랜 시뮬레이터

| 파일 | 용도 |
|---|---|
| `sogaebank_bonus_simulation_v0.2.xlsx` | **기준 엑셀**(대표 제공 시뮬레이터 + 검증 시트 4개) |
| `web/sogaebank-simulator.html` | 웹 시뮬레이터(엑셀과 같은 계산, 휴대폰·PC 브라우저) |
| `sogaebank_bonus_simulation_v0.2.accdb` | MS Access 버전: 입력·직급표·월간결과·민감도 표 + 쿼리 SQL |
| `sogaebank_bonus_simulation.xlsx` | 이전 수정안(v0.1) 비교용 |

## Access 파일 사용법
1. `.accdb`를 MS Access(2010 이상)로 엽니다.
2. [쿼리SQL] 표의 SQL을 [만들기] → [쿼리 디자인] → [SQL 보기]에 붙여 넣고 같은 이름으로 저장합니다.
3. [입력] 표의 값을 바꾼 뒤 `q_수당재계산`을 실행하면 월별 수당·지급률이 다시 계산됩니다(조직·매출은 저장값).

## Access 파일 다시 만들기 (Linux)
`access/tsv/*.tsv`를 고친 뒤 Jackcess 4.0.5(+commons-lang3, commons-logging)로 실행:
```bash
cd simulation/access && javac -cp "jars/*" Build.java
LC_ALL=C.UTF-8 java -Dsun.jnu.encoding=UTF-8 -cp "jars/*:." Build tsv ../sogaebank_bonus_simulation_v0.2.accdb
```
