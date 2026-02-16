-- Fire Control Radar for Stormworks
-- Optimized for tick performance while maintaining all inputs and outputs
-- Tracks up to 8 targets with predictive filtering and 3D coordinate transforms

-- Constants
local FOV_BASE = 180
local COLOR_MAX = 255
local TWO_PI = math.pi * 2
local PI = math.pi
local HISTORY_SIZE = 30
local FILTER_MASS = 10000
local FILTER_DAMPING = 0.1
local FILTER_FREQUENCY = 3

-- Cached functions for performance
local input_getBool = input.getBool
local input_getNumber = input.getNumber
local output_setBool = output.setBool
local output_setNumber = output.setNumber
local screen_setColor = screen.setColor
local screen_drawRectF = screen.drawRectF
local screen_drawRect = screen.drawRect
local screen_drawLine = screen.drawLine
local screen_drawText = screen.drawText
local screen_drawCircle = screen.drawCircle
local screen_getWidth = screen.getWidth
local screen_getHeight = screen.getHeight
local math_sin = math.sin
local math_cos = math.cos
local math_atan = math.atan
local math_sqrt = math.sqrt
local string_format = string.format
local table_insert = table.insert
local table_remove = table.remove
local property_getBool = property.getBool

-- State variables
local last_target = {x=0, y=0, z=0}
local distance_history = {}
local velocity_history = {}

-- Initialize history arrays
for i = 1, HISTORY_SIZE do
    distance_history[i] = 0
    velocity_history[i] = 0
end

-- Predictive filter (Kalman-like)
local function createFilter(mass, damping, frequency)
    return {
        position = 0,
        filtered_position = 0,
        velocity = 0,
        mass = mass,
        damping = damping,
        frequency = frequency,
        
        update = function(self, target_position, reset, noise_variance)
            self.mass = self.mass + self.damping
            local alpha = self.mass / (self.mass + noise_variance)
            
            local predicted = self.filtered_position + self.velocity
            local error = target_position - predicted
            
            self.filtered_position = predicted + alpha * error
            self.velocity = self.velocity + (alpha / 5) * error / self.frequency
            self.mass = (1 - alpha) * self.mass
            
            if reset then
                self.filtered_position = target_position
                self.velocity = 0
            end
        end
    }
end

-- Create filters for X, Y, Z coordinates
local filter_x = createFilter(FILTER_MASS, FILTER_DAMPING, FILTER_FREQUENCY)
local filter_y = createFilter(FILTER_MASS, FILTER_DAMPING, FILTER_FREQUENCY)
local filter_z = createFilter(FILTER_MASS, FILTER_DAMPING, FILTER_FREQUENCY)

-- Calculate 3D distance
local function distance3D(x, y, z)
    return math_sqrt(x * x + y * y + z * z)
end

-- Transform world coordinates to local coordinates using rotation matrix
local function transformToLocal(x, y, z, rotation_matrix)
    local m = rotation_matrix
    return m[1][1] * x + m[2][1] * y + m[3][1] * z,
           m[1][2] * x + m[2][2] * y + m[3][2] * z,
           m[1][3] * x + m[2][3] * y + m[3][3] * z
end

-- Build rotation matrix from pitch and roll angles
-- Pre-calculate sin/cos values to avoid redundant calculations
local function buildRotationMatrix(pitch, roll, yaw)
    local cp = math_cos(pitch)
    local sp = math_sin(pitch)
    local cr = math_cos(roll)
    local sr = math_sin(roll)
    local cy = math_cos(yaw)
    local sy = math_sin(yaw)
    
    return {
        {cy * cp, -sp, sy * cp},
        {cr * cy * sp + sr * sy, cr * cp, cr * sy * sp - sr * cy},
        {sr * cy * sp - cr * sy, sr * cp, sr * sy * sp + cr * cy}
    }
end

-- Build transpose of rotation matrix
local function transposeMatrix(matrix)
    return {
        {matrix[1][1], matrix[2][1], matrix[3][1]},
        {matrix[1][2], matrix[2][2], matrix[3][2]},
        {matrix[1][3], matrix[2][3], matrix[3][3]}
    }
end

-- Main tick function - runs every game tick
function onTick()
    -- Read base position and orientation
    local base_x = input_getNumber(4)
    local base_y = input_getNumber(12)
    local base_z = input_getNumber(8)
    local pitch = input_getNumber(16)
    local yaw = input_getNumber(24)
    local roll = input_getNumber(20)
    local zoom = input_getNumber(28)
    local track_mode = input_getBool(9)
    
    -- Build rotation matrices once
    local rotation_matrix = buildRotationMatrix(pitch, roll, yaw)
    local transpose_matrix = transposeMatrix(rotation_matrix)
    
    -- Calculate heading for output
    local heading_angle = math_atan(-rotation_matrix[2][1], rotation_matrix[2][2])
    
    -- Process up to 8 targets
    local targets = {}
    local active_targets = 0
    local target_active = {}
    local target_metrics = {}
    
    for i = 1, 8 do
        local is_active = input_getBool(i)
        target_active[i] = is_active
        
        if is_active then
            active_targets = active_targets + 1
            
            -- Read target data
            local distance = input_getNumber(4 * i - 3)
            local azimuth = input_getNumber(4 * i - 2) * TWO_PI
            local elevation = input_getNumber(4 * i - 1) * TWO_PI
            
            -- Convert spherical to Cartesian coordinates
            local cos_elev = math_cos(elevation)
            local x = distance * math_cos(azimuth) * cos_elev
            local y = distance * math_sin(azimuth) * cos_elev
            local z = distance * math_sin(elevation)
            
            -- Transform to world coordinates
            local world_x, world_y, world_z = transformToLocal(x, y, z, rotation_matrix)
            
            -- Store target with absolute position
            targets[active_targets] = {
                x = base_x + world_x,
                y = base_y + world_y,
                z = base_z + world_z,
                azimuth = azimuth,
                elevation = elevation
            }
            
            -- Pre-calculate metric for proximity detection
            local filter_distance = distance3D(
                filter_x.position - base_x,
                filter_y.position - base_y,
                filter_z.position - base_z
            )
            target_metrics[i] = {
                filter_distance / filter_distance,
                azimuth,
                elevation
            }
        end
    end
    
    -- Select target to track
    local selected_target_index = 1
    local min_distance = math.huge
    
    if track_mode then
        -- Track closest target to predicted position
        for i = 1, active_targets do
            local t = targets[i]
            local dx = t.x - filter_x.position
            local dy = t.y - filter_y.position
            local dz = t.z - filter_z.position
            local dist = math_sqrt(dx * dx + dy * dy + dz * dz)
            
            if dist < min_distance then
                min_distance = dist
                selected_target_index = i
            end
        end
    elseif target_active[1] then
        -- Free mode - use last active target
        selected_target_index = active_targets
    end
    
    -- Update filter with selected target
    if active_targets > 0 then
        local selected = targets[selected_target_index]
        
        -- Check if target changed significantly (reset filter if needed)
        local dx = selected.x - last_target.x
        local dy = selected.y - last_target.y
        local dz = selected.z - last_target.z
        local target_distance = math_sqrt(dx * dx + dy * dy + dz * dz)
        local reset = target_distance > 200
        
        -- Calculate noise variance based on distance to base
        local base_distance = distance3D(
            filter_x.filtered_position - base_x,
            filter_y.filtered_position - base_y,
            filter_z.filtered_position - base_z
        )
        local noise_variance = (base_distance * 0.02) * (base_distance * 0.02) / 12
        
        -- Update filters
        if target_active[1] then
            filter_x:update(selected.x, reset, noise_variance)
            filter_y:update(selected.y, reset, noise_variance)
            filter_z:update(selected.z, reset, noise_variance)
        end
        
        last_target = selected
    end
    
    -- Output filtered position and velocity
    if target_active[1] then
        output_setNumber(1, filter_x.filtered_position)
        output_setNumber(2, filter_y.filtered_position)
        output_setNumber(3, filter_z.filtered_position)
        output_setNumber(4, filter_x.velocity)
        output_setNumber(5, filter_y.velocity)
        output_setNumber(6, filter_z.velocity)
        output_setBool(2, property_getBool("use Proximity Fuze"))
    end
    
    -- Transform filtered position to local coordinates for display
    local local_x, local_y, local_z = transformToLocal(
        filter_x.filtered_position - base_x,
        filter_y.filtered_position - base_y,
        filter_z.filtered_position - base_z,
        transpose_matrix
    )
    
    -- Output heading angles
    local horizontal_dist = math_sqrt(local_x * local_x + local_y * local_y)
    output_setNumber(31, math_atan(local_z, horizontal_dist) / TWO_PI)
    output_setNumber(32, math_atan(local_x, local_y) / TWO_PI)
    
    -- Update history for display
    local current_distance = distance3D(
        filter_x.filtered_position - base_x,
        filter_y.filtered_position - base_y,
        filter_z.filtered_position - base_z
    )
    local current_velocity = distance3D(filter_x.velocity, filter_y.velocity, filter_z.velocity)
    
    table_insert(distance_history, current_distance)
    table_insert(velocity_history, current_velocity)
    
    while #distance_history > HISTORY_SIZE do
        table_remove(distance_history, 1)
    end
    while #velocity_history > HISTORY_SIZE do
        table_remove(velocity_history, 1)
    end
end

-- Draw function - runs every frame
function onDraw()
    local width = screen_getWidth()
    local height = screen_getHeight()
    
    -- Read current state for display
    local base_x = input_getNumber(4)
    local base_y = input_getNumber(12)
    local base_z = input_getNumber(8)
    local pitch = input_getNumber(16)
    local yaw = input_getNumber(24)
    local roll = input_getNumber(20)
    local zoom = input_getNumber(28)
    local track_mode = input_getBool(9)
    
    -- Calculate zoom-adjusted field of view
    local fov_scale = 132 * (1 - zoom) + 1.5 * zoom
    local rect_width = height * 0.07 * 360 / fov_scale
    local rect_height = rect_width
    
    -- Draw targeting reticle
    screen_setColor(0, COLOR_MAX, 0, 150)
    screen_drawRect(width / 2 - rect_width / 2, height / 2 - rect_height / 2, rect_width, rect_height)
    
    -- Build rotation matrices for display
    local rotation_matrix = buildRotationMatrix(pitch, roll, yaw)
    local transpose_matrix = transposeMatrix(rotation_matrix)
    
    -- Transform current filtered position to screen coordinates
    local current_x, current_y, current_z = transformToLocal(
        filter_x.filtered_position - base_x,
        filter_y.filtered_position - base_y,
        filter_z.filtered_position - base_z,
        transpose_matrix
    )
    
    local azimuth = math_atan(current_x, current_y)
    local horizontal = math_sqrt(current_x * current_x + current_y * current_y)
    local elevation = math_atan(current_z, horizontal)
    
    local screen_x = width / 2 + height * azimuth / (fov_scale * PI / FOV_BASE)
    local screen_y = height / 2 - height * elevation / (fov_scale * PI / FOV_BASE)
    
    -- Draw current target position
    screen_setColor(COLOR_MAX, 0, 0)
    screen_drawCircle(screen_x, screen_y, 4)
    
    -- Transform predicted position (current + 10 * velocity) to screen
    local predicted_x, predicted_y, predicted_z = transformToLocal(
        filter_x.filtered_position - base_x + 10 * filter_x.velocity,
        filter_y.filtered_position - base_y + 10 * filter_y.velocity,
        filter_z.filtered_position - base_z + 10 * filter_z.velocity,
        transpose_matrix
    )
    
    azimuth = math_atan(predicted_x, predicted_y)
    horizontal = math_sqrt(predicted_x * predicted_x + predicted_y * predicted_y)
    elevation = math_atan(predicted_z, horizontal)
    
    local pred_screen_x = width / 2 + height * azimuth / (fov_scale * PI / FOV_BASE)
    local pred_screen_y = height / 2 - height * elevation / (fov_scale * PI / FOV_BASE)
    
    -- Draw velocity vector
    screen_setColor(COLOR_MAX, COLOR_MAX, COLOR_MAX)
    screen_drawLine(screen_x, screen_y, pred_screen_x, pred_screen_y)
    
    -- Draw all active targets
    for i = 1, 8 do
        if input_getBool(i) then
            local azimuth = input_getNumber(4 * i - 2) * TWO_PI
            local elevation = input_getNumber(4 * i - 1) * TWO_PI
            
            if azimuth + elevation ~= 0 then
                local target_x = width / 2 + height * azimuth / (fov_scale * PI / FOV_BASE)
                local target_y = height / 2 - height * elevation / (fov_scale * PI / FOV_BASE)
                
                screen_setColor(COLOR_MAX, COLOR_MAX, 0)
                screen_drawRectF(target_x, target_y, 1, 1)
            end
        end
    end
    
    -- Calculate and display average distance and velocity
    local avg_distance = 0
    local avg_velocity = 0
    local count = #distance_history
    
    for i = 1, count do
        avg_distance = avg_distance + distance_history[i]
        avg_velocity = avg_velocity + velocity_history[i]
    end
    
    if count > 0 then
        avg_distance = avg_distance / count
        avg_velocity = avg_velocity / count
    end
    
    -- Display telemetry
    screen_setColor(0, 150, 23, 225)
    screen_drawText(1, 20, string_format("%.0fm", avg_distance))
    screen_drawText(1, 36, string_format("%.0f KPH", avg_velocity * 60 * 3.6))
    screen_drawText(1, 29, string_format("%.0f ALT", filter_z.filtered_position))
    
    -- Display mode
    screen_setColor(COLOR_MAX, 0, 0, 225)
    if track_mode then
        screen_drawText(width - 25, 15, "TRACK")
    else
        screen_drawText(width - 20, 15, "FREE")
    end
    
    -- Draw range indicator
    screen_setColor(0, 0, 0)
    screen_drawRectF(width - 11, height - 30, 11, 30)
    
    screen_setColor(0, 50, 0)
    local angle = 0.03 * TWO_PI
    for side = 1, 2 do
        local sign = (-1) ^ side
        screen_drawLine(
            width - 6,
            height - 1,
            width - 6 + 29 * math_sin(angle) * sign,
            height - 1 - 29 * math_cos(angle)
        )
    end
    
    -- Draw target range markers
    screen_setColor(COLOR_MAX, COLOR_MAX, 0)
    for i = 1, 8 do
        if input_getBool(i) then
            local distance = input_getNumber(4 * i - 3)
            local base_distance = distance3D(
                filter_x.filtered_position - base_x,
                filter_y.filtered_position - base_y,
                filter_z.filtered_position - base_z
            )
            local azimuth = input_getNumber(4 * i - 2) * TWO_PI
            local elevation = input_getNumber(4 * i - 1) * TWO_PI
            
            local ratio = distance / base_distance
            if ratio <= 1.05 then
                local marker_x = width - 6 + 28 * ratio * math_sin(azimuth)
                local marker_y = height - 1 - 28 * ratio * math_cos(elevation)
                screen_drawRectF(marker_x, marker_y, 1, 1)
            end
        end
    end
end
