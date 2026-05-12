# 모멘텀(Momentum) 게이지 개발 계획서

**작성일:** 2026-05-12
**기반 문서:** JustParkour.md §4 기획자 제안 ① 모멘텀(Momentum) 게이지
**대상 파일:** `main.lua` (단일 파일 아키텍처)

---

## 1. 기능 요약

멈추지 않고 파쿠르 액션(점프, 클라이밍, 크롤링)을 성공할 때마다 **Flow 게이지**가 상승하고,
게이지가 **Full**이 되면 캐릭터 뒤로 **네온 잔상**이 남으며 이동 속도가 **1.2배** 증가하는 시스템.

### 확정된 세부 사항

| 항목 | 결정 |
|------|------|
| 게이지 감소 조건 | idle 상태가 일정 시간 이상 지속되면 감소 |
| 액션별 충전량 | 동일 (점프 = 클라이밍 = 크롤링) |
| 네온 잔상 | Full 상태에서만 표시 |
| 속도 1.2배 적용 범위 | `RUN_SPEED`, `CRAWL_SPEED`, `JUMP_FWD_VX` 모두 적용 |
| Full 상태 지속 | idle 유지 시간에 따라 감소 (감소 조건과 동일) |

---

## 2. 설계

### 2.1 새로운 상수 (main.lua 상단)

```lua
-- ============ momentum gauge ============
local MOMENTUM_MAX        = 100    -- 게이지 최대값
local MOMENTUM_PER_ACTION = 20     -- 액션 1회당 충전량 (5회 액션으로 Full)
local MOMENTUM_IDLE_GRACE = 1.0    -- idle 후 감소가 시작되기까지의 유예 시간(초)
local MOMENTUM_DECAY_RATE = 40     -- 유예 시간 경과 후 초당 감소량
local MOMENTUM_SPEED_MULT = 1.2    -- Full 상태 속도 배율
local MOMENTUM_TRAIL_COUNT = 5     -- 네온 잔상 개수
local MOMENTUM_TRAIL_INTERVAL = 0.05 -- 잔상 기록 간격(초)
```

### 2.2 새로운 플레이어 필드 (`loadMap` 에서 초기화)

```lua
player.momentum       = 0       -- 현재 게이지 값 (0 ~ MOMENTUM_MAX)
player.idleTimer      = 0       -- idle 상태 누적 시간
player.momentumFull   = false   -- Full 상태 플래그 (캐시)
player.trail          = {}      -- 잔상 위치 링버퍼 {x, y, direction, quad, alpha}
player.trailTimer     = 0       -- 잔상 기록 타이머
```

### 2.3 게이지 충전 로직

**충전 트리거 시점** — 액션이 "성공적으로 완료"된 순간:

| 액션 | 트리거 시점 | 삽입 위치 |
|------|------------|-----------|
| **점프** | `triggerJumpFromState()` 호출 시 | `triggerJumpFromState` 함수 내, 점프 속도 설정 직후 |
| **클라이밍** | climb 애니메이션 완료, 장애물 윗면에 안착 시 | `updateAnimation` 내 `player.state == "climb"` 완료 분기 |
| **크롤링** | crawl 상태로 이동 중인 매 프레임 | 별도 처리 — 아래 참고 |

**크롤링 충전 방식:**
크롤링은 순간 동작이 아니라 지속 동작이므로, 일정 거리(`CRAWL_CHARGE_DIST`)를 이동할 때마다 1회 충전하는 방식으로 처리합니다.
```lua
local CRAWL_CHARGE_DIST = 80  -- 크롤링 80px 이동마다 1회 충전
```
`player.crawlDistAccum` 필드를 추가하여 크롤링 이동 거리를 누적하고, 임계값 도달 시 충전 후 리셋합니다.

**충전 함수:**
```lua
local function addMomentum()
    player.momentum = math.min(player.momentum + MOMENTUM_PER_ACTION, MOMENTUM_MAX)
    player.momentumFull = (player.momentum >= MOMENTUM_MAX)
    player.idleTimer = 0  -- 액션 수행 시 idle 타이머 리셋
end
```

### 2.4 게이지 감소 로직

`updatePlay(dt)` 내에서 매 프레임 처리:

```
if player.state == "idle" then
    player.idleTimer += dt
    if player.idleTimer > MOMENTUM_IDLE_GRACE then
        player.momentum -= MOMENTUM_DECAY_RATE * dt
        player.momentum = max(0, player.momentum)
        player.momentumFull = false  -- (momentum < MAX이므로)
    end
else
    player.idleTimer = 0
end
```

### 2.5 속도 배율 적용

기존 코드에서 속도 상수를 직접 사용하는 **4곳**을 수정합니다:

| 위치 | 기존 코드 | 변경 |
|------|-----------|------|
| `updateGroundedInput` L238 | `player.vx = CRAWL_SPEED` | `player.vx = CRAWL_SPEED * momentumMult()` |
| `updateGroundedInput` L240 | `player.vx = -CRAWL_SPEED` | `player.vx = -CRAWL_SPEED * momentumMult()` |
| `updateGroundedInput` L245 | `player.vx = RUN_SPEED` | `player.vx = RUN_SPEED * momentumMult()` |
| `updateGroundedInput` L247 | `player.vx = -RUN_SPEED` | `player.vx = -RUN_SPEED * momentumMult()` |
| `triggerJumpFromState` L481 | `player.vx = JUMP_FWD_VX` | `player.vx = JUMP_FWD_VX * momentumMult()` |
| `triggerJumpFromState` L486 | `player.vx = -JUMP_FWD_VX` | `player.vx = -JUMP_FWD_VX * momentumMult()` |

**헬퍼 함수:**
```lua
local function momentumMult()
    return player.momentumFull and MOMENTUM_SPEED_MULT or 1.0
end
```

**주의:** `JUMP_VY`(수직 점프 높이)에는 배율을 적용하지 않습니다 — 수직 점프는 수평 이동이 없으므로 속도 부스트 대상이 아닙니다.

### 2.6 네온 잔상 렌더링

**잔상 데이터 수집** (`updatePlay` 내):
- `player.momentumFull == true`일 때만 `trailTimer`를 갱신
- `MOMENTUM_TRAIL_INTERVAL`마다 현재 위치/방향/쿼드를 링버퍼(`player.trail`)에 기록
- 링버퍼 크기는 `MOMENTUM_TRAIL_COUNT`로 제한
- Full이 아니면 `player.trail`을 비워서 잔상이 즉시 사라지게 함

**잔상 그리기** (`drawPlayer` 직전, `love.draw`의 translate 블록 내):
```
for i, t in ipairs(player.trail) do
    alpha = 0.15 + 0.10 * (i / #player.trail)  -- 최신일수록 진하게
    setColor(0.2, 0.8, 1.0, alpha)              -- 네온 시안 색상
    draw(spriteSheet, t.quad, t.x, t.y - 32, 0, t.direction, 1, 32, 32)
end
```

색상은 네온 시안(`#33CCFF` 계열)을 기본으로 하되, 필요 시 튜닝 가능하도록 상수화합니다:
```lua
local TRAIL_COLOR = {0.2, 0.8, 1.0}  -- 네온 시안
```

### 2.7 HUD — 게이지 바 표시

`drawHUD` 함수에 게이지 바를 추가합니다:

- **위치:** 화면 상단 HUD 바 안, 맵 이름 오른쪽
- **크기:** 가로 100px, 세로 10px
- **색상:** 배경은 어두운 회색, 채워진 부분은 게이지 비율에 따라 시안→풀 시 밝은 시안+글로우
- **"FLOW" 텍스트:** 게이지 바 왼쪽에 소형 라벨

```
[Downtown          FLOW [████████░░] 80%          ESC: menu]
[Downtown          FLOW [██████████] MAX!         ESC: menu]  ← Full 시 색상 변경 + "MAX!"
```

---

## 3. 수행 목록

### 단계 1: 상수 및 초기화
- [ ] `main.lua` 상단에 모멘텀 관련 상수 7개 추가
- [ ] `loadMap()` 함수에 `player.momentum`, `player.idleTimer`, `player.momentumFull`, `player.trail`, `player.trailTimer`, `player.crawlDistAccum` 초기화 추가

### 단계 2: 핵심 로직
- [ ] `addMomentum()` 헬퍼 함수 추가
- [ ] `momentumMult()` 헬퍼 함수 추가
- [ ] `triggerJumpFromState()`에 점프 시 게이지 충전 호출 추가
- [ ] `updateAnimation()` climb 완료 분기에 게이지 충전 호출 추가
- [ ] `updatePlay()`에 크롤링 거리 누적 및 충전 로직 추가
- [ ] `updatePlay()`에 idle 감소 로직 추가

### 단계 3: 속도 배율 적용
- [ ] `updateGroundedInput()` 내 `RUN_SPEED`, `CRAWL_SPEED` 사용처 6곳에 `momentumMult()` 적용
- [ ] `triggerJumpFromState()` 내 `JUMP_FWD_VX` 사용처 2곳에 `momentumMult()` 적용

### 단계 4: 시각 효과
- [ ] 잔상 데이터 수집 로직 (`updatePlay` 내 링버퍼 관리)
- [ ] 잔상 렌더링 (`drawPlayer` 직전)
- [ ] HUD 게이지 바 (`drawHUD` 내)

### 단계 5: 검증
- [ ] luacheck 경고 확인
- [ ] 게임 실행 후 시각 검증
  - idle → 달리기 → 점프 → 클라이밍 반복으로 게이지 상승 확인
  - Full 도달 시 잔상 + 속도 부스트 확인
  - idle 유지 시 게이지 감소 확인
  - 맵 재시작(R키) 시 게이지 리셋 확인

### 단계 6: 문서 갱신
- [ ] `readme.md` 작업 내용에 모멘텀 게이지 구현 기록

---

## 4. 영향 분석

### 변경되는 기존 함수

| 함수 | 변경 내용 | 위험도 |
|------|-----------|--------|
| `loadMap()` | 필드 초기화 추가 | 낮음 |
| `updateGroundedInput()` | 속도에 배율 곱셈 | 낮음 — 기존 로직 구조 불변 |
| `triggerJumpFromState()` | 충전 호출 + 속도 배율 | 낮음 — 점프 입력 순서 무관 |
| `updatePlay()` | idle 감소 + 크롤링 충전 로직 추가 | 중간 — 프레임 순서 주의 |
| `updateAnimation()` | climb 완료 시 충전 호출 1줄 추가 | 낮음 |
| `drawPlayer()` 영역 | 잔상 렌더링 추가 (함수 자체는 변경 안 함) | 낮음 |
| `drawHUD()` | 게이지 바 추가 | 낮음 |

### 변경하지 않는 것

- `physicsStep()` — 물리 로직 자체는 건드리지 않음
- `setupAnimations()` — 스프라이트 시트 구조 변경 없음
- `updateCamera()` — 카메라 추적 속도는 모멘텀과 무관하게 유지
- `.tmx` 맵 파일들 — 맵 데이터 변경 없음
- 점프 입력 레이스 컨디션 처리 순서 — `jumpRequested` → `triggerJumpFromState` → `thisFrameKeys` 클리어 순서 유지

---

## 5. 튜닝 가이드

구현 후 플레이테스트에서 조절할 가능성이 높은 값들:

| 상수 | 현재 설계값 | 조절 방향 |
|------|------------|-----------|
| `MOMENTUM_PER_ACTION` | 20 (5회 = Full) | ↑ 쉬움 / ↓ 어려움 |
| `MOMENTUM_IDLE_GRACE` | 1.0초 | ↑ 관대 / ↓ 긴장감 |
| `MOMENTUM_DECAY_RATE` | 40/초 (2.5초에 전량 소진) | ↑ 빠른 소진 / ↓ 유지 |
| `MOMENTUM_SPEED_MULT` | 1.2 | ↑ 체감↑ / ↓ 밸런스 |
| `CRAWL_CHARGE_DIST` | 80px | ↑ 크롤링 기여↓ / ↓ 기여↑ |
