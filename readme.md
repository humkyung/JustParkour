# JustParkour

LÖVE2D로 만든 단일 파일 Parkour 횡스크롤 게임. 모든 로직은 [main.lua](main.lua)에 있습니다.

## 실행
- LÖVE2D 11.x 설치 후 `run.bat` 실행 (또는 프로젝트 루트에서 `love .`).

## 플레이어
- 스틱맨

## 플레이 흐름
- 게임을 로딩하면 플레이할 맵(도시)을 선택한다.
- 플레이어가 화면의 3/4 지점으로 이동하면 우→좌 스크롤이 되면서 오른쪽에 새로운 장애물들이 나타난다.
- 플레이어가 화면의 1/4 지점으로 이동하면 좌→우 스크롤이 되면서 왼쪽 이전 장애물들이 나타난다.
- 점프하여 장애물 옆면을 잡으면 자동으로 장애물 윗면까지 기어올라간다.
- 점프 시 효과음을 재생한다.
- 목표물에 안착하면 맵을 종료한다.

## 조작
| 키         | 동작           |
| --------- | ------------ |
| (입력 없음)   | 제자리 뛰기 애니메이션 |
| `d`       | 앞으로 달리기      |
| `a`       | 뒤로 달리기       |
| `w`       | 위로 점프        |
| `s`       | 엎드리기         |
| `w` + `d` | 앞으로 점프       |
| `w` + `a` | 뒤로 점프        |
| `s` + `d` | 앞으로 기어가기     |
| `s` + `a` | 뒤로 기어가기      |

## 액션 목록
- 앞으로/뒤로 달리기
- 위로 점프 / 앞으로 점프 / 뒤로 점프
- 엎드리기
- 앞으로/뒤로 기어가기
- 기어오르기(climb) : 벽 옆면을 잡고 기어올라 벽 상단까지 이동
	- 점프(w, w+d, w+a)후 벽 옆에 닿으면 기어오르기 자동 발동
- 벽 위를 달리다 벽을 벗어나면 땅으로 낙하

## 외부 툴
- 타일 에디터 : Titled Version 1.12.10
- 스프라이트 에디터
	- Piskel(https://www.piskelapp.com/p/create/sprite/)
## 개선 사항
- [x] 기어오르기 (점프 후 장애물 옆면을 잡으면 자동 발동) 애니메이션이 보이지 않음
- [x] w+d 키를 누르면 앞으로 점프(상방 45도 방향으로 점프) 기능 동작하지 않음
- [x] 기어오르기 애니메이션이 벽 옆면 제자리에서 일어남
	- 실제 벽 옆면을 기어 올라가야 함
- [x] w+d, w+a로 점프할때 너무 먼 거리로 점프함(점프 거리를 조금 줄여야 함)
- [x] w, w+d, w+a로 점프할 때 assets\jump.wav 효과음 발현
## 버그
- [x] 벽이 아닌 일반 평지에서도 w+d 키를 누르면 앞으로 점프(상방 45도 방향으로 점프) 기능 동작하지 않음
- [x] w, w+d, w+a 후 벽 옆면에 닿아도 기어오르기가 자동 발동하지 않음
- [x] 벽 윗면에서 이동하여 벽 끝에 도착하면 반대 방향의 끝으로 이동
- [x] w+d : 수직 점프가 아닌 45도 앞으로 점프
- [x] w+a : 수직 점프가 아닌 45도 뒤로 점프
## 작업 내용

- 2026-05-10: 하드코딩된 맵 데이터를 [Tiled 맵 에디터](https://www.mapeditor.org/) 호환 파일로 분리.
    - 편집용 마스터: `maps/downtown.tmx`, `maps/industrial_park.tmx`, `maps/rooftops.tmx`
    - 초기에는 게임 로딩용 `.lua` (Tiled "Export As Lua") 파일을 함께 두는 방식이었으나, 매 편집 후 export를 깜빡하면 게임에 반영되지 않는 문제가 있어 게임이 `.tmx`를 직접 파싱하도록 변경.
    - 장애물/목표는 Object Layer의 사각형으로, 이름/배경색/지면색/endX는 맵 custom property(또는 `<map>` 태그의 backgroundcolor)로 표현.
    - `main.lua`에 경량 .tmx 파서(`loadMapFromTMX`, `parseAttrs`)와 `hexToColor` 헬퍼 추가. 외부 라이브러리 의존성 없음.
- 2026-05-10: 기어가다 머리 위 장애물에 자동 기어오르기가 발동되는 버그 수정.
    - `updatePlay` 공중 분기에서 `s` 키가 눌려 있으면 `state`를 `"jump"` 대신 `"crawl"`/`"duck"`로 유지 → LOW hitbox 보존.
    - `physicsStep` 자동 기어오르기 검사를 `state`가 `"crawl"`/`"duck"`일 때 건너뜀 (사용자 명시 요구: "기어서 지나갈 때 벽 옆면에 닿더라도 올라가지 않도록").
- 2026-05-10: Piskel 기반 스프라이트 워크플로우 도입.
    - `assets/piskel/` 디렉토리 추가 — 애니메이션마다 별도 `.piskel` 프로젝트와 가로 strip PNG export를 보관.
    - `scripts/stitch_spritesheet.py` 추가 — strip 6개를 마스터 `assets/spritesheet.png`로 합치는 PIL 스크립트 (`--keep-existing` 옵션으로 부분 갱신 지원).
    - 프레임 수와 셀 크기는 현재 그대로 유지 (256×256, 4×4 그리드, 64px 셀)이므로 `setupAnimations()`/`drawPlayer()` 변경 없음.
    - 기존 `scripts/gen_spritesheet.py`는 더미 폴백으로만 보존.
- 2026-05-10: (롤백) `.piskel` 런타임 로딩(A안) 시도를 모두 되돌림. `main.lua`의 `jsonDecode`/`loadPiskelStrip`/`player.sprites` 폐기, `setupAnimations()`/`drawPlayer()`/`love.load()` 모두 단일 마스터 시트(`player.spriteSheet`) 방식으로 원복. `run`/`crawl`의 frame 인덱싱도 `{2, 3, 4, 3}` (마스터 시트 col 인덱스) 그대로 복원.
- 2026-05-10: 빌드 단계 변환(B안) 도입.
    - `scripts/piskel_to_spritesheet.py` 신규 작성 — 6개 `.piskel`을 직접 파싱(JSON + base64 + PIL)해서 `assets/spritesheet.png`로 합칩니다. `<name>.piskel`이 없으면 `<name>.png` 가로 strip을 폴백으로 사용해, Piskel 외 도구로 만든 strip도 같은 스크립트로 처리 가능. `--keep-existing`으로 부분 갱신 지원.
    - 기존 `scripts/stitch_spritesheet.py` 제거 — 새 스크립트가 `.png` strip 입력도 처리하므로 기능이 흡수됨.
    - 워크플로우: Piskel에서 `.piskel` 편집/저장 → `python scripts/piskel_to_spritesheet.py` → `love .`. (게임 코드는 무변경, 마스터 PNG만 갱신)
---
- 2026-05-12: 모멘텀(Flow) 게이지 시스템 구현.
    - 파쿠르 액션(점프, 클라이밍, 크롤링 80px 이동) 성공 시 게이지 충전 (5회로 Full).
    - idle 상태 1초 유예 후 초당 40씩 게이지 감소.
    - Full 시 이동 속도 1.2배 (`RUN_SPEED`, `CRAWL_SPEED`, `JUMP_FWD_VX` 적용) + 네온 시안 잔상 효과.
    - HUD에 Flow 게이지 바 표시 (Full 시 "MAX!" 라벨).
    - 개발 계획서: `docs/momentum_gauge_plan.md`