local camera = require "orthographic.camera"
local gesture = require "in.gesture"
local desktop_zoom_manager = require("lib.desktop_zoom_manager")
local pinch_zoom_manager_v2 = require("lib.pinch_zoom_manager_v2")

local CAMERA_MOVE_DURATION = 0.2

local scale_factor = 1
local GAME_SCREEN_W, GAME_SCREEN_H = window.get_size()
local GAME_OBJECTS_LAYER_Z = 0.9
local pick_item_attempts_controller_id = "/pick_item_attempts_controller"

local min_x = -GAME_SCREEN_W * scale_factor
local min_y = -GAME_SCREEN_H * scale_factor
local max_x = GAME_SCREEN_W * scale_factor
local max_y = GAME_SCREEN_H * scale_factor

local CAMERA_ID = "/camera"

-- @class InputActionsManager
local M = {}

function M.init()
    gesture.SETTINGS.double_tap_interval = 1
    gesture.SETTINGS.swipe_threshold = 20
    gesture.SETTINGS.swipe_time = 0.5
    gesture.SETTINGS.tap_threshold = 7

    M.is_moving = false
    M.is_swiping = false
    M.start_position = vmath.vector3()
    M.target_position = vmath.vector3()
    M.elapsed_time = 0

    desktop_zoom_manager.init()
end

function M.on_message(message_id, message, sender)
    desktop_zoom_manager.on_message(message_id, message)
end

function M.update(dt)
    if M.is_moving then
        M.elapsed_time = M.elapsed_time + dt
        local t = M.elapsed_time / CAMERA_MOVE_DURATION

        if t >= 1 then
            t = 1
            M.is_moving = false
        end

        local distance = math.sqrt(math.pow(M.target_position.x - M.start_position.x, 2) + 
                                 math.pow(M.target_position.y - M.start_position.y, 2))
        if distance < 10 then
            M.start_position = M.target_position
        end
        local new_pos = vmath.lerp(t, M.start_position, M.target_position)
        go.set_position(new_pos, CAMERA_ID)
    end
end

local function clamp_vector_length(vec, min_len, max_len)
    local len = vmath.length(vec)
    if len < min_len then
        return vmath.normalize(vec) * min_len
    elseif len > max_len then
        return vmath.normalize(vec) * max_len
    else
        return vec
    end
end

local function clamp_camera_position(pos, zoom)
    local visible_w = GAME_SCREEN_W / zoom
    local visible_h = GAME_SCREEN_H / zoom

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

local function calculate_min_swipe_distance()
    width, height = window.get_size()
    return math.sqrt(width * width + height * height) * 0.02
end

local function calculate_max_swipe_distance()
    width, height = window.get_size()
    return math.sqrt(width * width + height * height) * 0.25
end

local function resolve_crossplatform_game_action_type(action_id, action, g)
    if g then
        if g.swipe and g.swipe.to and g.swipe.from and 
           not pinch_zoom_manager_v2.is_in_pinch_mode() and 
           not action.touch then
            return "swipe"
        end
    end
    if action.released and action_id ~= hash("mouse_wheel_up") and action_id ~= hash("mouse_wheel_down") then
        if not action.touch and not pinch_zoom_manager_v2.is_in_pinch_mode() then
            return "place_touch_indicator"
        end
    end
end

local function resolve_desktop_game_action_type(action_id, action, g)
    if action_id == hash("mouse_wheel_up") then
        return "zoom_in"
    end
    if action_id == hash("mouse_wheel_down") then
        return "zoom_out"
    end
    return nil
end

local game_action_handlers = {
    place_touch_indicator = function(action, action_id, g)
        place_touch_indicator(action)
    end,
    zoom_in = function(action, action_id, g)
        desktop_zoom_manager.handle_zoom_in(clamp_camera_position)
    end,
    zoom_out = function(action, action_id, g)
        desktop_zoom_manager.handle_zoom_out(clamp_camera_position)
    end,
    pinch_zoom = function(action, action_id, g)
        --pinch_zoom_manager.handle_pinch_zoom(action, action_id, g, clamp_camera_position)
    end,
    swipe = function(action, action_id, g)
        local swipe_vector = g.swipe.to - g.swipe.from
        swipe_vector = swipe_vector * -1

        local min_swipe_distance = calculate_min_swipe_distance()
        local max_swipe_distance = calculate_max_swipe_distance()

        local clamped_vector = clamp_vector_length(swipe_vector, min_swipe_distance, max_swipe_distance)
        print('clamped_vector', clamped_vector)
        print('desktop_zoom_manager.get_current_zoom()', tostring(desktop_zoom_manager.get_current_zoom()))
        local adjusted_vector = clamped_vector / desktop_zoom_manager.get_current_zoom()

        local current_position = go.get_position(CAMERA_ID)
        M.start_position = current_position
        local raw_target_position = current_position + vmath.vector3(adjusted_vector.x, adjusted_vector.y, 0)
        M.target_position = clamp_camera_position(raw_target_position, desktop_zoom_manager.get_current_zoom())

        M.elapsed_time = 0
        M.is_moving = true
        M.is_swiping = true
    end
}

function M.handle_desktop_input(action_id, action, g)
    local game_action_type = resolve_desktop_game_action_type(action_id, action, g)
    if game_action_type and game_action_handlers[game_action_type] then
        game_action_handlers[game_action_type](action, action_id, g)
        return true
    end
    return false
end

function M.handle_crossplatform_input(action_id, action, g)
    if action.released then
        if M.is_swiping then
            M.is_swiping = false
            return
        end
    end
    
    local game_action_type = resolve_crossplatform_game_action_type(action_id, action, g)
    if game_action_type and game_action_handlers[game_action_type] then
        game_action_handlers[game_action_type](action, action_id, g)
        return true
    end
    return false
end

function M.on_input(action_id, action)

    local is_pinch_zoom_happening = pinch_zoom_manager_v2.on_input(action_id, action)
    if not is_pinch_zoom_happening then
    local g = gesture.on_input(M, action_id, action)
        if M.handle_crossplatform_input(action_id, action, g) then
            return
        end
        M.handle_desktop_input(action_id, action, g)
    end
 
end

return M