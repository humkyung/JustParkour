-- JustParkour: single-file LOVE2D parkour side-scroller.
-- Layout reference: assets/spritesheet.png is a 256x256 sheet of 64x64 cells.
--   Row 0: idle, run-2, run-3, run-4
--   Row 1: jump-1..jump-4
--   Row 2: duck, crawl-2, crawl-3, crawl-4
--   Row 3: climb-1..climb-4
-- The master sheet is built from assets/piskel/<state>.piskel by
-- scripts/piskel_to_spritesheet.py. Edit the .piskel files in Piskel, run the
-- script, then launch the game; setupAnimations() reads only the master PNG.

local SCREEN_W, SCREEN_H = 800, 450
local GROUND_Y           = 360
local GRAVITY            = 1500
local JUMP_VY            = -480           -- W (straight-up) vertical impulse; tall enough to clear typical obstacles
local JUMP_FWD_VX        = 400            -- W+D / W+A horizontal velocity (reduced from 480 for shorter jump distance)
local JUMP_FWD_VY        = -400           -- W+D / W+A vertical velocity (matches |vx| -> 45-degree initial angle)
local RUN_SPEED          = 240
local CRAWL_SPEED        = 90

local PLAYER_HALF_W      = 12
local PLAYER_TALL_H      = 52
local PLAYER_LOW_H       = 24

-- Per spec, any airborne side touch triggers auto-climb. CLIMB_REACH is the
-- horizontal "wingspan" added to the player box on the FACING side only, so
-- W (vertical) jumps next to a wall grab it without needing to penetrate, but
-- stepping off the far edge of an obstacle the player was standing on doesn't
-- accidentally re-grab it from behind.
local CLIMB_REACH        = 6              -- px of grab reach beyond the player's facing side

-- Camera follow uses a max speed so fast horizontal motion (W+D / W+A jumps)
-- visibly outpaces the camera. We use a higher cap on the ground (matches run)
-- and a much lower cap in the air so the 45-degree jump arc is clearly visible.
local CAMERA_FOLLOW_SPEED_GROUND = 320    -- >= RUN_SPEED; ground tracking stays tight
local CAMERA_FOLLOW_SPEED_AIR    = 140    -- << JUMP_FWD_VX; jump arc reads as a forward leap

-- 모멘텀(Flow) 게이지
local MOMENTUM_MAX            = 100     -- 게이지 최대값
local MOMENTUM_PER_ACTION     = 20      -- 액션 1회당 충전량 (5회로 Full)
local MOMENTUM_IDLE_GRACE     = 1.0     -- idle 후 감소 시작까지 유예 시간(초)
local MOMENTUM_DECAY_RATE     = 40      -- 유예 후 초당 감소량
local MOMENTUM_SPEED_MULT     = 1.2     -- Full 상태 속도 배율
local MOMENTUM_TRAIL_COUNT    = 5       -- 네온 잔상 개수
local MOMENTUM_TRAIL_INTERVAL = 0.05    -- 잔상 기록 간격(초)
local CRAWL_CHARGE_DIST       = 80      -- 크롤링 이 거리(px)마다 1회 충전
local TRAIL_COLOR             = {0.2, 0.8, 1.0}  -- 네온 시안

local gameState   -- "menu" | "play" | "win"
local camera = { x = 0 }
local player = {}
local maps = {}
local currentMapIdx = 1
local jumpRequested = false               -- set by love.keypressed("w"), consumed in love.update
-- Keys received via love.keypressed during the current frame. Used as a fallback
-- alongside love.keyboard.isDown so a quick W+D / W+A tap (where the modifier key
-- might already be released by the time love.update runs) still registers as held.
local thisFrameKeys = {}

-- ============ animation setup ============
local function setupAnimations()
    player.gridSize = 64
    local sheetW, sheetH = player.spriteSheet:getDimensions()
    player.animations = {
        idle  = { row = 0, frames = {1},          speed = 0.20, loop = true  },
        run   = { row = 0, frames = {2, 3, 4, 3}, speed = 0.10, loop = true  },
        jump  = { row = 1, frames = {1, 2, 3, 4}, speed = 0.15, loop = false },
        duck  = { row = 2, frames = {1},          speed = 0.20, loop = true  },
        crawl = { row = 2, frames = {2, 3, 4, 3}, speed = 0.15, loop = true  },
        climb = { row = 3, frames = {1, 2, 3, 4}, speed = 0.18, loop = false },
    }
    player.quads = {}
    for stateName, anim in pairs(player.animations) do
        player.quads[stateName] = {}
        for _, col in ipairs(anim.frames) do
            local q = love.graphics.newQuad(
                (col - 1) * player.gridSize,
                anim.row * player.gridSize,
                player.gridSize, player.gridSize, sheetW, sheetH
            )
            table.insert(player.quads[stateName], q)
        end
    end
end

-- ============ map data (Tiled .tmx loader) ============
-- Ordered list of Tiled .tmx files. The .tmx is the single source of truth —
-- edit in Tiled and the changes are picked up directly on the next launch
-- (no "Export As Lua" step required).
local MAP_FILES = {
    "maps/downtown.tmx",
    "maps/industrial_park.tmx",
    "maps/rooftops.tmx",
}

-- Convert a "#RRGGBB" or "#AARRGGBB" hex string to LÖVE's 0..1 RGB table.
local function hexToColor(hex)
    if hex:sub(1, 1) == "#" then hex = hex:sub(2) end
    if #hex == 8 then hex = hex:sub(3) end  -- drop alpha if present
    local r = tonumber(hex:sub(1, 2), 16) or 0
    local g = tonumber(hex:sub(3, 4), 16) or 0
    local b = tonumber(hex:sub(5, 6), 16) or 0
    return { r / 255, g / 255, b / 255 }
end

-- Pull XML-style key="value" attributes from a tag string into a table.
local function parseAttrs(tag)
    local attrs = {}
    for k, v in tag:gmatch('([%w_]+)%s*=%s*"([^"]*)"') do
        attrs[k] = v
    end
    return attrs
end

-- Minimal Tiled .tmx parser for the subset of the format we actually use:
--   <map ... backgroundcolor="#RRGGBB">
--     <properties>
--       <property name="name|groundColor|endX" value="..."/>
--     </properties>
--     <objectgroup name="obstacles">
--       <object x=".." y=".." width=".." height=".."/>
--     </objectgroup>
--     <objectgroup name="goal">
--       <object .../>
--     </objectgroup>
--   </map>
-- Tilesets, tile layers, polygons, and per-object properties are ignored —
-- this game only uses AABB rectangles on Object Layers.
local function loadMapFromTMX(path)
    local content = love.filesystem.read(path)
    if not content then
        error("Failed to read map: " .. path)
    end

    -- backgroundcolor lives on the <map ...> tag itself.
    local mapTag = content:match("<map[^>]*>") or ""
    local mapAttrs = parseAttrs(mapTag)

    -- Map-level <properties> appears in the header before any <objectgroup>.
    -- Restricting the scan to the header avoids picking up per-object
    -- <property> tags if they're ever added later.
    local headerEnd = content:find("<objectgroup") or #content
    local header = content:sub(1, headerEnd - 1)
    local props = {}
    for propTag in header:gmatch("<property%s+[^>]*>") do
        local pa = parseAttrs(propTag)
        if pa.name then props[pa.name] = pa.value end
    end

    local map = {
        name        = props.name or path,
        bgColor     = hexToColor(mapAttrs.backgroundcolor or "#000000"),
        groundColor = hexToColor(props.groundColor or "#202020"),
        endX        = tonumber(props.endX) or 1600,
        obstacles   = {},
        goal        = nil,
    }

    -- Walk each <objectgroup name="...">...</objectgroup> block. Object x/y
    -- in Tiled is the top-left of the rectangle in pixels, which matches
    -- what physicsStep / drawMap already expect (no GROUND_Y offset).
    for groupTag, body in content:gmatch("(<objectgroup[^>]*>)(.-)</objectgroup>") do
        local ga = parseAttrs(groupTag)
        for objTag in body:gmatch("<object%s+[^>]*>") do
            local oa = parseAttrs(objTag)
            local rect = {
                x = tonumber(oa.x)      or 0,
                y = tonumber(oa.y)      or 0,
                w = tonumber(oa.width)  or 0,
                h = tonumber(oa.height) or 0,
            }
            if ga.name == "obstacles" then
                table.insert(map.obstacles, rect)
            elseif ga.name == "goal" and not map.goal then
                map.goal = rect
            end
        end
    end

    return map
end

local function buildMaps()
    maps = {}
    for _, path in ipairs(MAP_FILES) do
        table.insert(maps, loadMapFromTMX(path))
    end
end

-- ============ level loading ============
local function loadMap(idx)
    currentMapIdx     = idx
    player.x          = 80
    player.y          = GROUND_Y
    player.vx         = 0
    player.vy         = 0
    player.onGround   = true
    player.state      = "idle"
    player.currentFrame = 1
    player.animTimer  = 0
    player.direction  = 1
    player.climbTarget = nil
    player.momentum      = 0
    player.idleTimer     = 0
    player.momentumFull  = false
    player.trail         = {}
    player.trailTimer    = 0
    player.crawlDistAccum = 0
    camera.x          = 0
end

-- ============ collision helpers ============
local function rectOverlap(ax, ay, aw, ah, bx, by, bw, bh)
    return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

local function getPlayerBox()
    local low = (player.state == "duck" or player.state == "crawl")
    local h   = low and PLAYER_LOW_H or PLAYER_TALL_H
    return player.x - PLAYER_HALF_W, player.y - h, PLAYER_HALF_W * 2, h
end

local function isKeyHeld(key)
    -- True if the key is currently held OR was pressed at any point during
    -- this frame's love.keypressed events. Lets brief W+D / W+A taps register
    -- the modifier even if the user has already released it by the time
    -- love.update runs.
    return love.keyboard.isDown(key) or thisFrameKeys[key] == true
end

local function addMomentum()
    player.momentum = math.min(player.momentum + MOMENTUM_PER_ACTION, MOMENTUM_MAX)
    player.momentumFull = (player.momentum >= MOMENTUM_MAX)
    player.idleTimer = 0
end

local function momentumMult()
    return player.momentumFull and MOMENTUM_SPEED_MULT or 1.0
end

local function startClimb(obs)
    player.state        = "climb"
    player.climbTarget  = obs
    player.climbStartY  = player.y
    player.currentFrame = 1
    player.animTimer    = 0
    player.vx           = 0
    player.vy           = 0
    -- Snap horizontally to the wall edge so the climb starts visibly attached
    -- to the obstacle rather than penetrating it.
    if player.direction == 1 then
        player.x = obs.x - PLAYER_HALF_W
    else
        player.x = obs.x + obs.w + PLAYER_HALF_W
    end
    -- Capture the start X (wall-outside) so updateAnimation can interpolate
    -- horizontally toward the top-inside position during the pull-up phase.
    player.climbStartX = player.x
end

-- ============ per-frame state derivation from input ============
local function updateGroundedInput()
    local kb = love.keyboard.isDown
    local mult = momentumMult()
    if kb("s") then
        if kb("d") then
            player.state = "crawl"; player.direction = 1;  player.vx = CRAWL_SPEED * mult
        elseif kb("a") then
            player.state = "crawl"; player.direction = -1; player.vx = -CRAWL_SPEED * mult
        else
            player.state = "duck"; player.vx = 0
        end
    elseif kb("d") then
        player.state = "run"; player.direction = 1; player.vx = RUN_SPEED * mult
    elseif kb("a") then
        player.state = "run"; player.direction = -1; player.vx = -RUN_SPEED * mult
    else
        player.state = "idle"; player.vx = 0
    end
end

-- ============ physics ============
local function physicsStep(dt)
    if player.state == "climb" then return end

    local map = maps[currentMapIdx]
    player.vy = player.vy + GRAVITY * dt

    -- ----- X axis -----
    local oldX = player.x
    player.x = player.x + player.vx * dt
    if player.x < 0 then player.x = 0; player.vx = 0 end

    do
        local px, py, pw, ph = getPlayerBox()

        -- Airborne climb detection: extend the player box only on the FACING
        -- side. Touching a wall in front (W, W+D, W+A) still auto-climbs, but
        -- a player who just stepped off the far edge of an obstacle won't
        -- have their trailing side reach back into the obstacle and re-grab it.
        -- Skip entirely while crawling/ducking — those are explicit "stay low"
        -- actions that must not be hijacked into a climb (e.g. crawling off a
        -- ledge into a slot under a low-hanging floating obstacle).
        if not player.onGround
           and player.state ~= "crawl"
           and player.state ~= "duck"
        then
            local rx, rw
            if player.direction == 1 then
                rx = px
                rw = pw + CLIMB_REACH
            else
                rx = px - CLIMB_REACH
                rw = pw + CLIMB_REACH
            end
            for _, obs in ipairs(map.obstacles) do
                if rectOverlap(rx, py, rw, ph, obs.x, obs.y, obs.w, obs.h) then
                    startClimb(obs)
                    return
                end
            end
        end

        -- Strict box check for movement blocking on the ground.
        for _, obs in ipairs(map.obstacles) do
            if rectOverlap(px, py, pw, ph, obs.x, obs.y, obs.w, obs.h) then
                player.x  = oldX
                player.vx = 0
                break
            end
        end
    end

    -- ----- Y axis -----
    local oldY = player.y
    player.y = player.y + player.vy * dt
    player.onGround = false

    if player.y >= GROUND_Y then
        player.y       = GROUND_Y
        player.vy      = 0
        player.onGround = true
    end

    do
        local px, py, pw, ph = getPlayerBox()
        for _, obs in ipairs(map.obstacles) do
            if rectOverlap(px, py, pw, ph, obs.x, obs.y, obs.w, obs.h) then
                if player.vy >= 0 and oldY <= obs.y + 1 then
                    -- landing on top
                    player.y       = obs.y
                    player.vy      = 0
                    player.onGround = true
                elseif player.vy < 0 then
                    -- hit head
                    player.y  = obs.y + obs.h + ph
                    player.vy = 0
                end
                break
            end
        end
    end
end

local function updateAnimation(dt)
    local anim = player.animations[player.state]
    player.animTimer = player.animTimer + dt

    -- Smoothly raise the player up the wall during the climb animation so the
    -- figure visibly ascends alongside the obstacle, then pulls onto the top
    -- in the final phase. Without this, the climb animation just plays in place.
    if player.state == "climb" and player.climbTarget then
        local obs    = player.climbTarget
        local total  = anim.speed * #anim.frames
        local elapsed = (player.currentFrame - 1) * anim.speed + player.animTimer
        local p = elapsed / total
        if p < 0 then p = 0 elseif p > 1 then p = 1 end

        -- Y: linear ascent from grab height to obstacle top across the whole climb.
        local startY = player.climbStartY or player.y
        player.y = startY + (obs.y - startY) * p

        -- X: stay on the wall side for the first 75% (climbing up), then pull
        -- onto the top in the last 25% (matches the climb-4 "stand on top" frame).
        local startX = player.climbStartX or player.x
        local endX
        if player.direction == 1 then
            endX = obs.x + PLAYER_HALF_W + 2
        else
            endX = obs.x + obs.w - PLAYER_HALF_W - 2
        end
        local pX = 0
        if p > 0.75 then pX = (p - 0.75) / 0.25 end
        player.x = startX + (endX - startX) * pX
    end

    if player.animTimer >= anim.speed then
        player.animTimer = player.animTimer - anim.speed
        player.currentFrame = player.currentFrame + 1
        if player.currentFrame > #anim.frames then
            if player.state == "climb" then
                local obs = player.climbTarget
                if obs then
                    player.y = obs.y
                    if player.direction == 1 then
                        player.x = obs.x + PLAYER_HALF_W + 2
                    else
                        player.x = obs.x + obs.w - PLAYER_HALF_W - 2
                    end
                end
                player.climbTarget = nil
                player.state       = "idle"
                player.onGround    = true
                player.vy          = 0
                addMomentum()
                player.currentFrame = 1
            elseif anim.loop then
                player.currentFrame = 1
            else
                player.currentFrame = #anim.frames
            end
        end
    end
end

local function updateCamera(dt)
    local screenX = player.x - camera.x
    local target = camera.x
    if screenX > SCREEN_W * 0.75 then
        target = player.x - SCREEN_W * 0.75
    elseif screenX < SCREEN_W * 0.25 then
        target = player.x - SCREEN_W * 0.25
    end

    -- Tighter follow on the ground; slower follow in the air so the 45-degree
    -- jump arc is clearly visible as the player visibly outpaces the camera.
    local maxSpeed = player.onGround and CAMERA_FOLLOW_SPEED_GROUND or CAMERA_FOLLOW_SPEED_AIR
    local diff = target - camera.x
    local maxStep = maxSpeed * dt
    if math.abs(diff) <= maxStep then
        camera.x = target
    elseif diff > 0 then
        camera.x = camera.x + maxStep
    else
        camera.x = camera.x - maxStep
    end

    if camera.x < 0 then camera.x = 0 end
    local map = maps[currentMapIdx]
    local maxCam = map.endX - SCREEN_W
    if maxCam < 0 then maxCam = 0 end
    if camera.x > maxCam then camera.x = maxCam end
end

local function checkGoal()
    local map = maps[currentMapIdx]
    local g   = map.goal
    local px, py, pw, ph = getPlayerBox()
    if player.onGround and rectOverlap(px, py, pw, ph, g.x, g.y, g.w, g.h) then
        gameState = "win"
    end
end

local function updatePlay(dt)
    if player.state ~= "climb" then
        local prevState = player.state
        if player.onGround then
            updateGroundedInput()
        else
            local kb = love.keyboard.isDown
            if kb("d") then player.direction = 1
            elseif kb("a") then player.direction = -1 end
            -- Preserve a low-profile state (and the LOW collision box) while
            -- airborne if S is held. Lets the player crawl off a ledge into a
            -- narrow gap (e.g. the slot between a tall obstacle's top and a
            -- floating obstacle's bottom) without their TALL hitbox colliding
            -- with the overhead obstacle and triggering auto-climb.
            if kb("s") then
                if kb("d") or kb("a") then
                    player.state = "crawl"
                else
                    player.state = "duck"
                end
            else
                player.state = "jump"
            end
        end
        if player.state ~= prevState then
            player.currentFrame = 1
            player.animTimer    = 0
        end
    end

    -- 모멘텀: idle 감소
    if player.state == "idle" then
        player.idleTimer = player.idleTimer + dt
        if player.idleTimer > MOMENTUM_IDLE_GRACE then
            player.momentum = math.max(0, player.momentum - MOMENTUM_DECAY_RATE * dt)
            player.momentumFull = false
        end
    else
        player.idleTimer = 0
    end

    -- 모멘텀: 크롤링 거리 누적 충전
    if player.state == "crawl" then
        player.crawlDistAccum = player.crawlDistAccum + math.abs(player.vx) * dt
        if player.crawlDistAccum >= CRAWL_CHARGE_DIST then
            player.crawlDistAccum = player.crawlDistAccum - CRAWL_CHARGE_DIST
            addMomentum()
        end
    else
        player.crawlDistAccum = 0
    end

    -- 모멘텀: 잔상 수집
    if player.momentumFull then
        player.trailTimer = player.trailTimer + dt
        if player.trailTimer >= MOMENTUM_TRAIL_INTERVAL then
            player.trailTimer = player.trailTimer - MOMENTUM_TRAIL_INTERVAL
            local quad = player.quads[player.state][player.currentFrame]
            table.insert(player.trail, {
                x = player.x, y = player.y,
                direction = player.direction, quad = quad
            })
            if #player.trail > MOMENTUM_TRAIL_COUNT then
                table.remove(player.trail, 1)
            end
        end
    else
        for i = #player.trail, 1, -1 do
            table.remove(player.trail, i)
        end
        player.trailTimer = 0
    end

    physicsStep(dt)
    updateAnimation(dt)
    updateCamera(dt)
    checkGoal()
end

-- Triggers a jump using the keyboard state at the moment update runs (i.e.,
-- AFTER all of this frame's key events have been processed). This eliminates
-- the race condition where a simultaneous W+D press could resolve W's
-- keypressed event before D's was polled, missing the forward boost.
local function triggerJumpFromState()
    if not (player.onGround and player.state ~= "climb") then return end
    player.onGround  = false
    addMomentum()
    local mult = momentumMult()
    if isKeyHeld("d") then
        -- W+D -> forward jump at 45 degrees up-right (|vx| == |vy|),
        -- shorter range than a pure-vertical jump.
        player.direction = 1
        player.vx        = JUMP_FWD_VX * mult
        player.vy        = JUMP_FWD_VY
    elseif isKeyHeld("a") then
        -- W+A -> backward jump at 45 degrees up-left, same shorter range.
        player.direction = -1
        player.vx        = -JUMP_FWD_VX * mult
        player.vy        = JUMP_FWD_VY
    else
        -- W only -> straight up jump (taller, no horizontal travel).
        player.vx        = 0
        player.vy        = JUMP_VY
    end
    player.state        = "jump"
    player.currentFrame = 1
    player.animTimer    = 0
    if player.sfxJump then
        player.sfxJump:stop()
        player.sfxJump:play()
    end
end

-- ============ drawing ============
local function drawBackdrop(map)
    love.graphics.clear(map.bgColor[1], map.bgColor[2], map.bgColor[3])

    -- distant skyline silhouette (parallax-light)
    love.graphics.setColor(0, 0, 0, 0.12)
    local plx = -camera.x * 0.3
    for i = 0, 20 do
        local bx = plx + i * 90
        local bh = 50 + ((i * 37) % 70)
        love.graphics.rectangle("fill", bx, GROUND_Y - bh, 60, bh)
    end
end

local function drawMap(map)
    -- ground
    love.graphics.setColor(map.groundColor)
    love.graphics.rectangle("fill", 0, GROUND_Y, map.endX, SCREEN_H - GROUND_Y)

    -- obstacles
    for _, obs in ipairs(map.obstacles) do
        love.graphics.setColor(0.18, 0.20, 0.24)
        love.graphics.rectangle("fill", obs.x, obs.y, obs.w, obs.h)
        love.graphics.setColor(0.45, 0.48, 0.55)
        love.graphics.rectangle("fill", obs.x, obs.y, obs.w, 3)  -- top highlight
    end

    -- goal: pole + flag
    local g = map.goal
    love.graphics.setColor(0.85, 0.85, 0.85)
    love.graphics.rectangle("fill", g.x, g.y, g.w, g.h)
    love.graphics.setColor(0.95, 0.25, 0.25)
    love.graphics.polygon("fill",
        g.x + g.w, g.y,
        g.x + g.w + 32, g.y + 14,
        g.x + g.w, g.y + 28
    )
end

local function drawTrail()
    for i, t in ipairs(player.trail) do
        local alpha = 0.15 + 0.10 * (i / #player.trail)
        love.graphics.setColor(TRAIL_COLOR[1], TRAIL_COLOR[2], TRAIL_COLOR[3], alpha)
        love.graphics.draw(
            player.spriteSheet, t.quad,
            t.x, t.y - 32,
            0,
            t.direction, 1,
            32, 32
        )
    end
end

local function drawPlayer()
    love.graphics.setColor(1, 1, 1)
    local quad = player.quads[player.state][player.currentFrame]
    love.graphics.draw(
        player.spriteSheet, quad,
        player.x, player.y - 32,
        0,
        player.direction, 1,
        32, 32
    )
end

local function drawHUD(map)
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", 0, 0, SCREEN_W, 28)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(map.name, 10, 7)

    -- Flow 게이지 바
    local barX, barY, barW, barH = SCREEN_W / 2 - 60, 8, 120, 12
    love.graphics.setColor(0.75, 0.78, 0.82)
    love.graphics.print("FLOW", barX - 40, 7)
    love.graphics.setColor(0.15, 0.15, 0.15)
    love.graphics.rectangle("fill", barX, barY, barW, barH)
    local ratio = player.momentum / MOMENTUM_MAX
    if ratio > 0 then
        if player.momentumFull then
            love.graphics.setColor(TRAIL_COLOR[1], TRAIL_COLOR[2], TRAIL_COLOR[3])
        else
            love.graphics.setColor(0.1, 0.5, 0.7)
        end
        love.graphics.rectangle("fill", barX, barY, barW * ratio, barH)
    end
    love.graphics.setColor(0.5, 0.5, 0.5)
    love.graphics.rectangle("line", barX, barY, barW, barH)
    if player.momentumFull then
        love.graphics.setColor(TRAIL_COLOR[1], TRAIL_COLOR[2], TRAIL_COLOR[3])
        love.graphics.print("MAX!", barX + barW + 4, 7)
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.print("ESC: menu", SCREEN_W - 90, 7)
end

local function drawMenu()
    love.graphics.clear(0.10, 0.12, 0.16)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("JustParkour", 30, 25, 0, 2.2, 2.2)
    love.graphics.print("Select a map (press 1-" .. #maps .. ")", 30, 90)
    for i, m in ipairs(maps) do
        love.graphics.print(string.format("[%d] %s", i, m.name), 50, 120 + (i - 1) * 22)
    end
    love.graphics.setColor(0.75, 0.78, 0.82)
    love.graphics.print("Controls", 30, 250)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("D: run forward    A: run back", 50, 272)
    love.graphics.print("W: jump up    W+D / W+A: jump fwd / back", 50, 290)
    love.graphics.print("S: duck    S+D / S+A: crawl fwd / back", 50, 308)
    love.graphics.print("Touch obstacle side mid-jump to auto-climb", 50, 326)
    love.graphics.print("Reach the red flag to clear the map", 50, 344)
    love.graphics.setColor(0.6, 0.6, 0.6)
    love.graphics.print("ESC: quit", 30, SCREEN_H - 28)
end

local function drawWin()
    local map = maps[currentMapIdx]
    drawBackdrop(map)
    love.graphics.push()
    love.graphics.translate(-camera.x, 0)
    drawMap(map)
    drawPlayer()
    love.graphics.pop()

    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 0, 0, SCREEN_W, SCREEN_H)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("MAP CLEARED!", SCREEN_W / 2 - 70, SCREEN_H / 2 - 30, 0, 2.2, 2.2)
    love.graphics.print("Press ENTER to return to the map list", SCREEN_W / 2 - 130, SCREEN_H / 2 + 20)
end

-- ============ love callbacks ============
function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")

    player.spriteSheet = love.graphics.newImage("assets/spritesheet.png")
    setupAnimations()

    -- Optional jump SFX (loaded only if file exists)
    if love.filesystem.getInfo("assets/jump.wav") then
        player.sfxJump = love.audio.newSource("assets/jump.wav", "static")
    elseif love.filesystem.getInfo("assets/jump.ogg") then
        player.sfxJump = love.audio.newSource("assets/jump.ogg", "static")
    end

    buildMaps()
    gameState = "menu"
end

function love.update(dt)
    if dt > 0.05 then dt = 0.05 end
    if gameState == "play" then
        -- Process any queued jump request now that all of this frame's key
        -- events have been polled. triggerJumpFromState uses isKeyHeld which
        -- consults both love.keyboard.isDown and thisFrameKeys, so a quick
        -- W+D / W+A tap still registers the modifier even if it has already
        -- been released by the time this runs.
        if jumpRequested then
            jumpRequested = false
            triggerJumpFromState()
        end
        updatePlay(dt)
    else
        -- Drop stale requests if the game is not in play.
        jumpRequested = false
    end
    -- Clear per-frame key cache after all input-dependent logic has run.
    for k in pairs(thisFrameKeys) do thisFrameKeys[k] = nil end
end

function love.draw()
    if gameState == "menu" then
        drawMenu()
    elseif gameState == "play" then
        local map = maps[currentMapIdx]
        drawBackdrop(map)
        love.graphics.push()
        love.graphics.translate(-camera.x, 0)
        drawMap(map)
        drawTrail()
        drawPlayer()
        love.graphics.pop()
        drawHUD(map)
    elseif gameState == "win" then
        drawWin()
    end
end

function love.keypressed(key)
    -- Record every key pressed during this frame so input checks elsewhere
    -- (notably the jump trigger) can see brief taps reliably.
    thisFrameKeys[key] = true
    if gameState == "menu" then
        if key == "escape" then
            love.event.quit()
        else
            local idx = tonumber(key)
            if idx and maps[idx] then
                loadMap(idx)
                gameState = "play"
            end
        end
    elseif gameState == "play" then
        if key == "escape" then
            gameState = "menu"
        elseif key == "r" then
            loadMap(currentMapIdx)
        elseif key == "w" then
            -- Defer jump trigger to love.update so that simultaneous W+D presses
            -- always see kb("d") = true regardless of the order events are polled.
            jumpRequested = true
        end
    elseif gameState == "win" then
        if key == "return" or key == "kpenter" or key == "space" then
            gameState = "menu"
        end
    end
end
