# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

JustParkour는 LÖVE2D(11.x) 기반의 단일 파일 횡스크롤 파쿠르 게임입니다. 게임플레이 로직, 물리, 애니메이션, 입력, 그리기는 모두 [main.lua](main.lua) 한 파일에 있고, 맵 데이터만 [Tiled 맵 에디터](https://www.mapeditor.org/) 형식인 `maps/*.tmx`에서 런타임에 로드됩니다. [readme.md](readme.md)는 한국어로 작성된 설계 명세서로, 조작 키, 액션 목록, 그리고 변경 작업의 기준이 되는 버그/개선 사항 체크리스트와 작업 내역을 담고 있습니다. 의도된 동작에 대해서는 이 문서를 기준 문서로 사용하세요.

## 실행 방법

```
love .              # love가 PATH에 등록되어 있는 경우
run.bat             # Windows: love를 먼저 시도하고, 없으면 C:\Program Files\LOVE\love.exe 사용
```

빌드 단계와 테스트 스위트는 없습니다. 변경 사항은 직접 게임을 플레이하면서 검증해야 합니다.

린터로 [luacheck](https://github.com/lunarmodules/luacheck)을 사용합니다. 설정은 [.luacheckrc](.luacheckrc)에 있습니다.

```
luacheck main.lua          # 전체 검사
luacheck main.lua -q       # 경고/에러만 출력
```

코드를 수정한 뒤에는 luacheck를 한 번 돌려 새로 생긴 경고가 없는지 확인하세요. LÖVE 콜백(`love.load/update/draw/keypressed`)은 전역으로 정의되어야 하므로 `.luacheckrc`에서 명시적으로 허용되어 있습니다 — 새 콜백을 추가할 때 unused-global 경고가 뜨면 진짜 오타인지 먼저 의심한 뒤, 정당한 콜백이라면 설정을 갱신하세요.

`conf.lua`에서 LÖVE 모듈 중 `physics`, `video`, `touch`, `joystick`이 비활성화되어 있습니다. 게임패드/터치 입력 등을 추가하려면 [conf.lua](conf.lua)를 먼저 수정해야 합니다.

선택적 점프 효과음은 `assets/jump.wav`가 있으면 자동으로 로드되고, 없으면 `assets/jump.ogg`를 시도합니다. 둘 다 없으면 무음으로 동작합니다([main.lua:529](main.lua:529)).

## 스프라이트 (Piskel → 마스터 PNG 빌드 단계)

스프라이트는 [Piskel](https://www.piskelapp.com/)로 편집한 6개의 `.piskel` 파일을 원본으로 두고, `scripts/piskel_to_spritesheet.py` 스크립트가 마스터 `assets/spritesheet.png`(256×256, 4×4 그리드, 64×64 셀)로 빌드합니다. 게임은 마스터 PNG만 로드하므로 `main.lua`의 `setupAnimations()`/`drawPlayer()`는 단순 시트 + Quad 방식 그대로입니다.

```
assets/piskel/
  idle.piskel    (1 frame  → row 0, col 0)
  run.piskel     (3 frames → row 0, cols 1..3)
  jump.piskel    (4 frames → row 1, cols 0..3)
  duck.piskel    (1 frame  → row 2, col 0)
  crawl.piskel   (3 frames → row 2, cols 1..3)
  climb.piskel   (4 frames → row 3, cols 0..3)
```

스틱맨은 **오른쪽**을 향하고 있으며, `player.direction = -1`일 때 `love.graphics.draw`에서 음수 X-스케일로 뒤집힙니다. `drawPlayer`의 원점이 `(32, 32)`(셀 중심), 그려지는 위치가 `player.y - 32`(`player.y`는 발 위치)이므로 캐릭터는 발이 셀 하단 근처에 오도록 그립니다.

### 워크플로우

1. **편집**: Piskel에서 `assets/piskel/<state>.piskel`을 열어 편집·저장.
2. **빌드**: `python scripts/piskel_to_spritesheet.py` 실행 → `assets/spritesheet.png` 갱신.
    - 일부만 갱신할 때: `--keep-existing`을 붙이면 발견된 입력만 덮어쓰고 나머지는 기존 시트에서 보존.
3. **검증**: `love .` 실행 후 6개 상태(idle/run/jump/duck/crawl/climb) 시각 확인.

`piskel_to_spritesheet.py`는 두 가지 입력 형식을 우선순위대로 처리합니다.

- 1순위: `assets/piskel/<name>.piskel` (Piskel 네이티브, 평소 워크플로우)
- 2순위 폴백: `assets/piskel/<name>.png` (가로 strip PNG, 다른 도구에서 만든 경우)

`.piskel`은 단일 chunk + 가로 strip(layout = `[[0],[1],...]`) 형태만 지원합니다. Piskel에서 단순 애니메이션을 만들면 자동으로 이 형태가 되지만, 다중 chunk나 격자 layout은 명시적 오류로 거부합니다.

### 시트 레이아웃 / 프레임 수를 바꿀 때

`main.lua`의 `setupAnimations()`(행/프레임 인덱스), `scripts/piskel_to_spritesheet.py`의 `LAYOUT` 상수, 그리고 .piskel/png 입력의 프레임 수가 모두 동기화되어야 합니다. `drawPlayer()`의 원점 `(32, 32)`은 셀 크기를 64에서 바꿀 때만 함께 손보면 됩니다.

### 관련 보조 스크립트

- `scripts/gen_spritesheet.py`: 초기 절차 생성 스틱맨으로 마스터 PNG를 만드는 폴백. 백지 상태에서 빠른 더미가 필요할 때만 사용.
- `scripts/split_spritesheet.py`: 마스터 시트를 16개 64×64 PNG로 쪼개 `assets/piskel/cells/`에 시맨틱 이름(`idle.png`, `run-2.png`, ..., `climb-4.png`)으로 저장. Piskel에 개별 프레임으로 import하거나 다시 그릴 때 참고용.

일상 워크플로우는 "Piskel 편집 → `piskel_to_spritesheet.py` → `love .`" 세 단계입니다.

## 단일 파일에서는 한눈에 보이지 않는 아키텍처 노트

### 단일 파일 레이아웃

`main.lua`는 위에서 아래로 다음 순서로 구성되어 있습니다: 상수 → 애니메이션 셋업 → 맵 데이터 → 레벨 로딩 → 충돌 헬퍼 → 입력 → 물리 → 애니메이션 틱 → 카메라 → 목표(goal) → 프레임 업데이트 → 그리기 → LÖVE 콜백. LÖVE 콜백(`love.load/update/draw/keypressed`)은 파일 맨 아래에 위치하며 위쪽의 헬퍼 함수들을 호출합니다.

### 게임 상태

`gameState`는 `"menu" | "play" | "win"` 중 하나입니다. `love.update`와 `love.draw`는 이 값에 따라 분기합니다. 메뉴에서 `1`–`#maps` 숫자 키는 `loadMap(idx)`를 호출하고 `"play"`로 전환합니다. 플레이 중 `ESC`는 메뉴로, `r`은 현재 맵을 즉시 재시작합니다(디버깅 시 유용). win 상태에서 `ENTER`/`SPACE`는 메뉴로 복귀합니다.

### 점프 입력 레이스 컨디션 (중요)

같은 프레임에 W와 D를 누르면, D가 `love.keyboard.isDown`으로 폴링되기 전에 `keypressed("w")`가 먼저 전달될 수 있습니다. 짧게 W+D / W+A 탭으로 입력했을 때 전진 부스트가 누락되지 않도록 다음과 같이 처리합니다.

1. `love.keypressed("w")`는 `jumpRequested = true` 플래그만 세팅합니다.
2. `love.update`는 해당 프레임의 모든 키 이벤트가 도착한 *이후*에 이 플래그를 소비하여 `triggerJumpFromState()`를 호출합니다.
3. `triggerJumpFromState`는 `isKeyHeld("d"/"a")`를 검사하는데, 이 함수는 `love.keyboard.isDown`과 `thisFrameKeys`(이번 프레임에 눌린 키를 `love.keypressed`가 채운 집합)를 OR로 결합합니다. update가 실행되는 시점에 이미 떼어진 탭도 잡아냅니다.
4. `thisFrameKeys`는 점프 트리거 이후, `love.update`의 **끝**에서 비워집니다.

점프나 입력 동작을 변경할 때는 이 순서를 반드시 유지해야 합니다. 그렇지 않으면 명세서에 적힌 W+D/W+A 버그가 다시 발생합니다.

### 자동 기어오르기(auto-climb) 메커니즘

명세에 따라 공중에서 장애물 옆면에 닿으면 `startClimb`이 발동됩니다. 기어오르기 감지용 충돌 박스는 **플레이어가 바라보는 방향(facing side) 쪽으로만** `CLIMB_REACH`(6 px)만큼 확장됩니다. 덕분에 W(수직) 점프는 정면 벽을 잡을 수 있지만, 자신이 서 있던 장애물의 반대쪽 끝에서 발을 내딛을 때 뒷면이 다시 장애물을 잡아채는 일은 일어나지 않습니다. 이동을 막는 충돌 검사에는 여전히 확장되지 않은 원래 박스를 사용합니다.

`updateAnimation`은 기어오르기 애니메이션 동안 플레이어의 X/Y를 보간하여 캐릭터가 실제로 벽을 따라 올라가는 것처럼 보이게 만듭니다. Y는 전체 기어오르기 구간에서 선형으로 상승하고, X는 처음 75%의 프레임 동안 벽 옆면에 붙어 있다가 마지막 25%에서 윗면으로 끌어올려집니다(climb-4의 "윗면에 서기" 프레임과 일치). 마지막 프레임에서 플레이어는 장애물 윗면에 스냅되고 상태가 `"idle"`로 전환됩니다.

### 카메라

`updateCamera`는 플레이어를 화면의 ¼ 지점과 ¾ 지점 사이에 유지합니다. 추적 속도는 의도적으로 **공중에서 더 느리게**(`CAMERA_FOLLOW_SPEED_AIR = 140`) 설정되어 있어, 지상에서의 속도(`CAMERA_FOLLOW_SPEED_GROUND = 320`)보다 낮습니다. 이는 45° W+D / W+A 점프의 포물선 궤적이 카메라보다 빠르게 움직이는 것이 시각적으로 드러나도록 하기 위함입니다. UX적인 명확한 이유 없이 두 속도를 동일하게 만들지 마세요.

### 물리(Physics) 특이사항

- 단일 지면 라인이 `GROUND_Y = 360`에 있고, 장애물은 모서리 처리가 없는 AABB입니다.
- Y축 충돌은 윗면 착지(`vy >= 0 and oldY <= obs.y + 1`)와 머리 박치기(`vy < 0`)를 구분합니다. `oldY`는 Y 이동 단계 *이전*에 캡처되므로, 이 순서를 유지해야 합니다.
- `physicsStep`은 `player.state == "climb"`일 때 즉시 반환하며, 기어오르기 동작은 전적으로 `updateAnimation`이 구동합니다.
- `dt`는 `love.update`에서 0.05로 클램핑되어, 프레임이 튈 때 터널링(빠른 충돌 누락)을 줄입니다.
- `getPlayerBox()`는 `state`가 `duck`/`crawl`일 때 충돌 박스 높이를 `PLAYER_TALL_H`(52) 대신 `PLAYER_LOW_H`(24)로 줄입니다. 즉, 낮게 매달린 장애물 밑을 기어 통과하는 게임플레이가 자세 상태에 의존합니다 — 자세 전환 키(`s`)를 건드릴 때 함께 검토해야 합니다.
- 공중에서 `s`가 눌려 있으면 `updatePlay`는 `state`를 `"jump"` 대신 `"crawl"`/`"duck"`로 유지합니다. 덕분에 LOW hitbox가 그대로 적용되어, 장애물 위에서 기어가다 끝에서 떨어질 때 머리 위 floating 장애물에 부딪혀 `physicsStep`의 자동 기어오르기가 발동되지 않습니다. 또한 climb 검사 자체도 `state`가 `crawl`/`duck`일 때 건너뜁니다 — "기어가는 중에는 절대 climb 안 함" 규칙입니다.

### 맵 데이터 (Tiled .tmx 직접 로딩)

런타임의 `maps` 테이블은 `buildMaps()`가 `MAP_FILES`에 나열된 `.tmx` 파일을 순서대로 파싱해 만든 결과입니다. `.tmx`가 단일 진실 원천(single source of truth)이며 별도의 export 단계는 없습니다 — Tiled에서 `.tmx`를 편집·저장하고 게임을 재실행하면 그대로 반영됩니다.

파서는 [main.lua](main.lua)의 `loadMapFromTMX` / `parseAttrs` / `hexToColor`로 구성되며, Tiled .tmx 형식 중 다음 부분 집합만 사용합니다.

- `<map ... backgroundcolor="#RRGGBB">` → 맵의 `bgColor`
- 헤더의 `<properties>` 안의 `<property name="..." value="..."/>` → `name` (문자열), `groundColor` (hex 문자열), `endX` (정수)
- `<objectgroup name="obstacles">`의 모든 `<object .../>` → `obstacles` 배열 (AABB)
- `<objectgroup name="goal">`의 첫 `<object .../>` → `goal` 사각형 (깃대+깃발 영역)

타일셋, 타일 레이어, 폴리곤, 회전된 객체, 객체별 properties는 무시합니다. 전부 axis-aligned 사각형이라는 가정이 기존 충돌/그리기 코드와 맞물려 있습니다. Tiled 객체의 `x`, `y`는 사각형의 좌상단 픽셀 좌표이며, 이는 `physicsStep`/`drawMap`이 기대하는 좌표계와 동일하므로 별도 변환이 필요 없습니다 (예전처럼 `GROUND_Y - h`로 환산하지 마세요).

새 맵을 추가하는 절차:

1. Tiled에서 `maps/<이름>.tmx`를 만들고 다음을 구성합니다.
    - 맵 background color (16진)
    - Custom properties: `name` (문자열), `groundColor` (`#RRGGBB`), `endX` (int)
    - Object Layer `obstacles`: 장애물 사각형들
    - Object Layer `goal`: 깃대+깃발 영역 사각형 1개
2. [main.lua](main.lua)의 `MAP_FILES` 배열 끝에 새 경로를 추가합니다. 메뉴는 `1..#maps`를 자동으로 나열하므로 추가 작업이 필요 없습니다.

`hexToColor`는 `#RRGGBB`와 `#AARRGGBB`(앞쪽 알파 바이트는 버림)를 모두 받습니다. `goal.y`는 더 이상 `GROUND_Y - height`로 자동 계산되지 않습니다 — Tiled에서 `y` 좌표를 직접 지정하므로, `GROUND_Y`를 바꾸면 모든 `.tmx`의 obstacles/goal `y`도 함께 손봐야 합니다.

## 컨벤션

- 명세서 [readme.md](readme.md)는 한글로, **새로 추가하거나 수정하는 코드 주석도 한글로 작성하세요**. 기존 영어 주석은 그대로 두며, 강제로 한글화할 필요는 없습니다. 코드 식별자(변수/함수 이름)는 영어 그대로 둡니다. 버그를 수정할 때는 readme.md의 버그/개선 사항 목록에서 해당 `[ ]` 항목도 함께 체크하세요.
- 모든 튜닝 가능한 값은 `main.lua` 상단에 SCREAMING_SNAKE_CASE의 `local` 상수로 정의되어 있습니다. 함수 안에 매직 넘버를 흩뿌리기보다 이 상수를 조정하세요.
## 중요
- 작업을 마친 후에 내용을 간략하게 명세서 [readme.md](readme.md)의 **작업 내용**에 날짜 포함해서 기입해주세요.