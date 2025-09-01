
local camera = require "orthographic.camera"

-- Constants
local ZOOM_STEP = 0.2
local MAX_ZOOM_IN = 2.25

local CAMERA_ID = "/camera"

local M = {}

--- Initialize the pinch zoom manager
function M.init()
    M.min_zoom = 0.5
    M.pinch_base_zoom = nil
    M.current_zoom = 1
    M.in_pinch_zoom_mode_timer = nil
end

--- Handle zoom in action
--- @param clamp_camera_fn function|nil
function M.handle_zoom_in(clamp_camera_fn)
    local new_zoom = math.min(M.current_zoom + ZOOM_STEP, MAX_ZOOM_IN)
    print('Zooming in: ', new_zoom)
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
function M.handle_zoom_out(clamp_camera_fn)
    local new_zoom = math.max(M.current_zoom - ZOOM_STEP, M.min_zoom)
    print('Zooming out: ', new_zoom)
    if new_zoom ~= M.current_zoom then
        M.current_zoom = new_zoom
        camera.set_zoom(nil, M.current_zoom)
        if clamp_camera_fn then
            local clamped_pos = clamp_camera_fn(go.get_position(CAMERA_ID), M.current_zoom)
            go.set_position(clamped_pos, CAMERA_ID)
        end
    end
end

--- Get current zoom level
--- @return number
function M.get_current_zoom()
    return M.current_zoom
end

return M