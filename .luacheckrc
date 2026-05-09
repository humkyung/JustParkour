std = "lua54+love"

read_globals = {
    "love",
}

ignore = {
    "212",  -- unused argument (LÖVE 콜백의 dt 등)
    "542",  -- empty if branch
}

files["main.lua"] = {
    -- main.lua는 LÖVE 콜백을 전역으로 정의해야 합니다(love.load/update/draw/keypressed).
    globals = { "love" },
}
