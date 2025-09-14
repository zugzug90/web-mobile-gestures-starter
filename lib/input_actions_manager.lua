local CAMERA_ID = "/camera"


local camera = require "orthographic.camera"

local GAME_OBJECTS_LAYER_Z = 0.9
local pick_item_attempts_controller_id = "/pick_item_attempts_controller"
local INERTIA = 0.75

local TOUCH_MULTI = hash("touch_multi")
local TOUCH = hash("touch")

-- Constants
local ZOOM_STEP = 1

local function clamp_camera_position(pos, zoom)

    local scale_factor = 1
    local window_width, window_height = window.get_size()
    local min_x = -window_width * 1 * scale_factor
    local min_y = -window_height * 1 * scale_factor
    local max_x = window_width * 1 * scale_factor
    local max_y = window_height * 1 * scale_factor

    local visible_w = window_width / zoom
    local visible_h = window_height / zoom

    local half_w = visible_w / 2
    local half_h = visible_h / 2

    local allowed_min_x = min_x + half_w
    local allowed_max_x = max_x - half_w
    local allowed_min_y = min_y + half_h
    local allowed_max_y = max_y - half_h

    local clamped_x = math.max(allowed_min_x, math.min(allowed_max_x, pos.x))
    local clamped_y = math.max(allowed_min_y, math.min(allowed_max_y, pos.y))

    return vmath.vector3(clamped_x, clamped_y, pos.z)
end

local function screen_to_world(camera, x, y, z, camera_id)
    return camera.screen_to_world(camera_id, vmath.vector3(x, y, z))
end

local function place_touch_indicator(action)
    local world_pos = screen_to_world(camera, action.x, action.y, 0)
    world_pos.z = GAME_OBJECTS_LAYER_Z
    print("Placing touch indicator at world position: ", world_pos)
    msg.post(pick_item_attempts_controller_id, hash("msg.create_pick_item_attempt_indicator"), { position = world_pos })
end

--- @class InputActionsManager
--- @field zoom_speed number Speed (pace) of zooming in/out
--- @field min_zoom number limit of zooming out - default is 1
--- @field max_zoom number limit of zooming in - default is 2.25
--- @field min_swipe_distance number min swipe distance in pixels to distinguish swipe from tap/click. Default is 10
--- @field zoom_step number single zoom in / zoom out step delta. Default is 0.2
--- @field clamp_camera_position_function function<vector3, number> function to clamp camera position to game level borders after zooming and when navigating
--- @field on_single_tap_function function<table> function to execute custom logic on single tap (click). Receives Defold input "action" table as argument.
local M = {
    controls_locked = false,
    zoom_speed = 0.1,
    current_zoom = 1,
    min_zoom = 1,
    min_swipe_distance = 10,
    zoom_step = ZOOM_STEP,
    max_zoom = 2.25,
    clamp_camera_position_function = clamp_camera_position,
    on_single_tap_function = place_touch_indicator
}

local function pinch_update(M, dt)
    -- Пинч если есть позици двух тапав и предыдущие значения
    if M.p1 and M.p2 and M.f_p1 and M.f_p2 then
        -- local w0 = (self.f_p2 - self.f_p1)
        -- local w1 = (self.p2 - self.p1)
        -- Вектора между тапами в мировых координатах

        local w0 = screen_to_world(camera, M.f_p2.x, M.f_p2.y, M.f_p2.z) - screen_to_world(camera, M.f_p1.x, M.f_p1.y, M.f_p1.z)
        local w1 = screen_to_world(camera, M.p2.x, M.p2.y, M.p2.z) - screen_to_world(camera, M.p1.x, M.p1.y, M.p1.z)

        -- Calculate the distance between points for both frames
        local prev_distance = vmath.length(w0)
        local curr_distance = vmath.length(w1)
        
        -- Determine if it's pinch in or out
        local is_pinch_in = curr_distance < prev_distance
        local is_pinch_out = curr_distance > prev_distance

        -- Масштаб
    
        --go.set(M.camera_go_id, "position.z", vmath.clamp(z, 300, 940))
        --camera.set_zoom(nil, scale)
        if is_pinch_in then
            M.handle_zoom_out(M.clamp_camera_position_function, dt)
        elseif is_pinch_out then
            M.handle_zoom_in(M.clamp_camera_position_function, dt)
        end

        M.is_pinch_zooming = true
    end

    -- перемещение камеры с инерцией
    M.cam_translate = (M.cam_translate or vmath.vector3(0)) * INERTIA

    pprint('vmath.length(M.cam_translate)', vmath.length(M.cam_translate))

    if M.translate then
        if M.prev_translate then
            local p = screen_to_world(camera, M.translate.x, M.translate.y, M.translate.z) - screen_to_world(camera, M.prev_translate.x, M.prev_translate.y, M.prev_translate.z)
            M.cam_translate = p
        end
    end
    M.prev_translate = M.translate
    M.translate = nil

    -- само перемещение + границы
    if vmath.length(M.cam_translate) > M.min_swipe_distance and not M.is_pinch_zooming and not M.p2 then
        local position = go.get_position(CAMERA_ID) - M.cam_translate

        position = M.clamp_camera_position_function(position, camera.get_zoom())

        go.set_position(position, CAMERA_ID)

        M.is_moving = true
    else
        timer.delay(0, false, function ()
            M.is_moving = false
        end)
    end

    -- запоминаем текущие позиции для следующего кадра
    M.f_p1 = M.p1
    M.f_p2 = M.p2
    M.p1 = nil
    M.p2 = nil
    M.is_pinch_zooming = nil
end

local function pinch_on_input(M, action_id, action)
    local ret = true
    -- обрабатываем мультитач
    if action_id == TOUCH_MULTI then
        for i, v in ipairs(action.touch) do
            if i == 1 then
                M.p1 = vmath.vector3(v.x, v.y, 0)
            elseif i == 2 then
                M.p2 = vmath.vector3(v.x, v.y, 0)
            end
        end
    -- сингловый тач (на мульти тоже придет на первый тап + мышка имитирует тач)
    elseif action_id == TOUCH and not action.touch then
        M.translate = vmath.vector3(action.x, action.y, 0)

        if action.pressed then
            M.single_touch_point = vmath.vector3(action.x, action.y, 0)
        end

        if action.released and not (M.is_pinch_zooming or M.is_moving) then

            if M.single_touch_point and vmath.length(M.single_touch_point - vmath.vector3(action.x, action.y, 0)) < M.min_swipe_distance then
                -- это клик, а не свайп
                M.on_single_tap_function(action)
                M.single_touch_point = nil
            elseif not M.single_touch_point then
                M.on_single_tap_function(action)
            end
        elseif action.released then
            timer.delay(0, false, function (self, handle, time_elapsed)
                M.is_pinch_zooming = false
                M.is_moving = false
                M.single_touch_point = nil
            end)
        end
    end

    return ret
end

M.update = function(dt)
    pinch_update(M, dt)
end

--- Handle zoom in action
--- @param clamp_camera_fn function|nil
function M.handle_zoom_in(clamp_camera_fn, dt)
    local effective_dt = dt or 0.16
    local new_zoom = math.min(M.current_zoom + M.zoom_step * effective_dt, M.max_zoom)
    if new_zoom ~= M.current_zoom then
        M.current_zoom = new_zoom
        camera.set_zoom(nil, M.current_zoom)
        if clamp_camera_fn then
            local clamped_pos = clamp_camera_fn(go.get_position(CAMERA_ID), M.current_zoom)
            go.set_position(clamped_pos, CAMERA_ID)
        end
    end
end

--- Handle zoom out action
--- @param clamp_camera_fn function|nil
function M.handle_zoom_out(clamp_camera_fn, dt)
    local effective_dt = dt or 0.16
    local new_zoom = math.max(M.current_zoom - M.zoom_step * effective_dt, M.min_zoom)
    if new_zoom ~= M.current_zoom then
        M.current_zoom = new_zoom
        camera.set_zoom(nil, M.current_zoom)
        if clamp_camera_fn then
            local clamped_pos = clamp_camera_fn(go.get_position(CAMERA_ID), M.current_zoom)
            go.set_position(clamped_pos, CAMERA_ID)
        end
    end
end

M.on_input = function(action_id, action)

    -- зум мышкой
    if true then
        if action_id == hash("mouse_wheel_up") then
            M.handle_zoom_in(M.clamp_camera_position_function)
            return true
        elseif action_id == hash("mouse_wheel_down") then
            M.handle_zoom_out(M.clamp_camera_position_function)
            return true
        end
    end

    -- мульти-пульти и мув камеры (универсальный мышкой и тачем) 
    if pinch_on_input(M, action_id, action) then return true end
end

--- @class InputActionsManagerOptions
--- @field is_mobile boolean    
--- @field min_swipe_distance number|nil min swipe distance in pixels to distinguish swipe from tap/click. Default is 10    
--- @field initial_zoom number|nil initial zoom level on game start. Default is 1
--- @field mobile_zoom_step number|nil single zoom in / zoom out step delta for mobile. Default is 0.2
--- @field mobile_min_zoom number|nil limit of zooming out for mobile - default is 1
--- @field mobile_max_zoom number|nil limit of zooming in for mobile - default is 2.25
--- @field min_zoom number|nil limit of zooming in for desktop - default is 1
--- @field max_zoom number|nil limit of zooming in for desktop - default is 2.25
--- @field clamp_camera_position_function function<vector3, number>|nil function to clamp camera position to game level borders after zooming and when navigating
--- @field on_single_tap_function function<table>|nil function to execute custom logic on single tap (click). Receives Defold input "action" table as argument.

---Initialize the game level input actions manager
---@param options InputActionsManagerOptions
function M.init(options)
    M.current_zoom = options.initial_zoom
    M.min_swipe_distance = options.min_swipe_distance or M.min_swipe_distance
    M.min_zoom = options.min_zoom or M.min_zoom
    M.max_zoom = options.max_zoom or M.max_zoom
    if options.is_mobile then
        M.zoom_step = options.mobile_zoom_step or M.zoom_step
        M.min_zoom = options.mobile_min_zoom or M.min_zoom
        M.max_zoom = options.mobile_max_zoom or M.max_zoom
    end
    M.clamp_camera_position_function = options.clamp_camera_position_function or M.clamp_camera_position_function
    M.on_single_tap_function = options.on_single_tap_function or M.on_single_tap_function
    
end

return M