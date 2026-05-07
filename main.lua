-- JustParkour: single-file LOVE2D parkour side-scroller.
-- Layout reference: assets/spritesheet.png is a 256x256 sheet of 64x64 cells.
--   Row 0: idle, run-2, run-3, run-4
--   Row 1: jump-1..jump-4
--   Row 2: duck, crawl-2, crawl-3, crawl-4
--   Row 3: climb-1..climb-4

local SCREEN_W, SCREEN_H = 800, 450
local GROUND_Y           = 360
local GRAVITY            = 1500
local JUMP_VY            = -520
local JUMP_VX_BOOST      = 70
local RUN_SPEED          = 220
local CRAWL_SPEED        = 90

local PLAYER_HALF_W      = 12
local PLAYER_TALL_H      = 52
local PLAYER_LOW_H       = 24

local gameState   -- "menu" | "play" | "win"
local camera = { x = 0 }
local player = {}
local maps = {}
local currentMapIdx = 1

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
        climb = { row = 3, frames = {1, 2, 3, 4}, speed = 0.12, loop = false },
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

-- ============ map data ============
local function buildMaps()
    maps = {
        {
            name        = "Downtown",
            bgColor     = { 0.55, 0.70, 0.88 },
            groundColor = { 0.30, 0.32, 0.36 },
            obstacles   = {
                { x = 380,  y = GROUND_Y - 60,  w = 80,  h = 60 },
                { x = 600,  y = GROUND_Y - 110, w = 90,  h = 110 },
                { x = 820,  y = GROUND_Y - 40,  w = 160, h = 40 },
                { x = 1080, y = GROUND_Y - 130, w = 80,  h = 130 },
                { x = 1260, y = GROUND_Y - 80,  w = 120, h = 80 },
            },
            goal        = { x = 1450, y = GROUND_Y - 160, w = 16, h = 160 },
            endX        = 1600,
        },
        {
            name        = "Industrial Park",
            bgColor     = { 0.45, 0.55, 0.65 },
            groundColor = { 0.25, 0.27, 0.30 },
            obstacles   = {
                { x = 350,  y = GROUND_Y - 50,  w = 100, h = 50 },
                { x = 520,  y = GROUND_Y - 100, w = 70,  h = 100 },
                { x = 700,  y = GROUND_Y - 160, w = 70,  h = 160 },
                { x = 880,  y = GROUND_Y - 100, w = 70,  h = 100 },
                { x = 1050, y = GROUND_Y - 50,  w = 200, h = 50 },
                { x = 1320, y = GROUND_Y - 140, w = 80,  h = 140 },
            },
            goal        = { x = 1500, y = GROUND_Y - 180, w = 16, h = 180 },
            endX        = 1700,
        },
        {
            name        = "Rooftops",
            bgColor     = { 0.85, 0.55, 0.45 },
            groundColor = { 0.35, 0.25, 0.22 },
            obstacles   = {
                { x = 300,  y = GROUND_Y - 90,  w = 80,  h = 90 },
                { x = 480,  y = GROUND_Y - 140, w = 80,  h = 140 },
                { x = 660,  y = GROUND_Y - 90,  w = 80,  h = 90 },
                { x = 820,  y = GROUND_Y - 180, w = 90,  h = 180 },
                { x = 1010, y = GROUND_Y - 100, w = 140, h = 100 },
                { x = 1240, y = GROUND_Y - 60,  w = 80,  h = 60 },
            },
            goal        = { x = 1380, y = GROUND_Y - 200, w = 16, h = 200 },
            endX        = 1500,
        },
    }
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

local function startClimb(obs)
    player.state        = "climb"
    player.climbTarget  = obs
    player.currentFrame = 1
    player.animTimer    = 0
    player.vx           = 0
    player.vy           = 0
end

-- ============ per-frame state derivation from input ============
local function updateGroundedInput()
    local kb = love.keyboard.isDown
    if kb("s") then
        if kb("d") then
            player.state = "crawl"; player.direction = 1;  player.vx = CRAWL_SPEED
        elseif kb("a") then
            player.state = "crawl"; player.direction = -1; player.vx = -CRAWL_SPEED
        else
            player.state = "duck"; player.vx = 0
        end
    elseif kb("d") then
        player.state = "run"; player.direction = 1; player.vx = RUN_SPEED
    elseif kb("a") then
        player.state = "run"; player.direction = -1; player.vx = -RUN_SPEED
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
        for _, obs in ipairs(map.obstacles) do
            if rectOverlap(px, py, pw, ph, obs.x, obs.y, obs.w, obs.h) then
                if not player.onGround then
                    -- jumping into the side of an obstacle -> auto-climb to top
                    startClimb(obs)
                    return
                else
                    player.x  = oldX
                    player.vx = 0
                    break
                end
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
                player.currentFrame = 1
            elseif anim.loop then
                player.currentFrame = 1
            else
                player.currentFrame = #anim.frames
            end
        end
    end
end

local function updateCamera()
    local screenX = player.x - camera.x
    if screenX > SCREEN_W * 0.75 then
        camera.x = player.x - SCREEN_W * 0.75
    elseif screenX < SCREEN_W * 0.25 then
        camera.x = player.x - SCREEN_W * 0.25
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
            player.state = "jump"
        end
        if player.state ~= prevState then
            player.currentFrame = 1
            player.animTimer    = 0
        end
    end

    physicsStep(dt)
    updateAnimation(dt)
    updateCamera()
    checkGoal()
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
        updatePlay(dt)
    end
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
        drawPlayer()
        love.graphics.pop()
        drawHUD(map)
    elseif gameState == "win" then
        drawWin()
    end
end

function love.keypressed(key)
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
        elseif key == "w" and player.onGround and player.state ~= "climb" then
            local kb = love.keyboard.isDown
            player.vy        = JUMP_VY
            player.onGround  = false
            if kb("d") then
                player.direction = 1
                player.vx        = RUN_SPEED + JUMP_VX_BOOST
            elseif kb("a") then
                player.direction = -1
                player.vx        = -(RUN_SPEED + JUMP_VX_BOOST)
            else
                player.vx = 0
            end
            player.state        = "jump"
            player.currentFrame = 1
            player.animTimer    = 0
            if player.sfxJump then
                player.sfxJump:stop()
                player.sfxJump:play()
            end
        end
    elseif gameState == "win" then
        if key == "return" or key == "kpenter" or key == "space" then
            gameState = "menu"
        end
    end
end
