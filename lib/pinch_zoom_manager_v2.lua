local camera = require "orthographic.camera"

local M = {}

M.zoom = 1.0
M._touches = {}
M._prev_distance = nil

M.min_zoom = 0.5
M.max_zoom = 2.25
M.smooth = 0.2 -- коэффициент сглаживания (0..1)

local function distance(t1, t2)
    local dx = t2.x - t1.x
    local dy = t2.y - t1.y
    return math.sqrt(dx*dx + dy*dy)
end

-- линейная интерполяция
local function lerp(a, b, t)
    return a + (b - a) * t
end

function M.on_input(action_id, action)
    -- одиночное касание
    if action_id == hash("touch") then
        if action.pressed then
            M._touches[action.id or 0] = {x = action.x, y = action.y}
        elseif action.released then
            M._touches[action.id or 0] = nil
            M._prev_distance = nil
            timer.delay(0.2, false, function (self, handle, time_elapsed)
                M.in_pinch_zoom_mode = false
            end)
        else
            M._touches[action.id or 0] = {x = action.x, y = action.y}
        end
    end

    -- мультитач
    if action_id == hash("touch_multi") then
        for _, touch in ipairs(action.touch) do
            if touch.pressed then
                M._touches[touch.id] = {x = touch.x, y = touch.y}
            elseif touch.released then
                M._touches[touch.id] = nil
                M._prev_distance = nil
            else
                M._touches[touch.id] = {x = touch.x, y = touch.y}
            end
        end
    end

    -- обработка pinch zoom
    local keys = {}
    for id, _ in pairs(M._touches) do
        keys[#keys+1] = id
    end

    if #keys == 2 then
        local t1 = M._touches[keys[1]]
        local t2 = M._touches[keys[2]]
        local d = distance(t1, t2)

        if M._prev_distance then
            local scale = d / M._prev_distance
            if scale ~= 1 then
                local target_zoom = M.zoom * scale
                -- применяем clamp
                target_zoom = math.min(M.max_zoom, math.max(M.min_zoom, target_zoom))
                -- сглаживаем к целевому
                M.zoom = lerp(M.zoom, target_zoom, M.smooth)
                camera.set_zoom(nil, M.zoom)
            end
            return true
        end
        M._prev_distance = d
        M.in_pinch_zoom_mode = true
    end

    return nil
end

--- Check if currently in pinch mode
--- @return boolean
function M.is_in_pinch_mode()
    return M.in_pinch_zoom_mode
end

return M
