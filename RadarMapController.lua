-- Radar Map Controller for Ship Microcontroller
-- Displays radar contacts, weapon systems, and navigation data on a map display

-- Constants
MAX_TARGETS = 128
RADAR_RANGE = 16666
MIN_MATCHING_DISTANCE = 150
MIN_DETECTION_DISTANCE = 5
ZOOM_MIN = 1
ZOOM_MAX = 50
TARGET_TIMEOUT = 310
SMOOTHING_OLD = 0.3
SMOOTHING_NEW = 0.7
UPDATE_INTERVAL = 30

-- Compass Arrow Display Constants
COMPASS_ARROW_TIP_RADIUS = 7
COMPASS_ARROW_BASE_RADIUS = 5
COMPASS_ARROW_LEFT_OFFSET = 0.4
COMPASS_ARROW_RIGHT_OFFSET = 0.6

-- Global State
TRACKED_TARGETS = {}
NEXT_TARGET_INDEX = 1
SCREEN_WIDTH = 0
SCREEN_HEIGHT = 0
ZOOM = 50
ZOOM_IN_CLICKED = false
ZOOM_OUT_CLICKED = false
RESET_CLICKED = false
UPDATE_COUNTER = 0

-- Ship Position and Orientation
SHIP_GPS_X = 0
SHIP_GPS_Y = 0
SHIP_HEADING = 0

-- Weapon System Positions
SAM_GPS_X = 0
SAM_GPS_Y = 0
GUN_GPS_X = 0
GUN_GPS_Y = 0
SSM_GPS_X = 0
SSM_GPS_Y = 0

-- Radar State
COMPASS_INPUT = 0
RADAR_ANGLE = 0
RADAR_ENABLED = false

-- Touch Input
TOUCH_X = 0
TOUCH_Y = 0
TOUCH_ACTIVE = false

-- Speed and Heading Display
SHIP_SPEED = 0
SHIP_HEADING_DEGREES = 0
RWR_WARNING = false

-- Cache commonly used functions
local cos = math.cos
local sin = math.sin
local sqrt = math.sqrt
local pi = math.pi
local mapToScreen = map.mapToScreen
local getNumber = input.getNumber
local getBool = input.getBool
local drawCircle = screen.drawCircle
local drawCircleF = screen.drawCircleF

-- Utility Functions

--- Clamp a value between min and max
--- @param value number The value to clamp
--- @param min number Minimum value
--- @param max number Maximum value
--- @return number The clamped value
function Clamp(value, min, max)
	return value < min and min or (value > max and max or value)
end

--- Get fractional part of a number
--- @param value number The input value
--- @return number The fractional part
function Frac(value)
	if value < 0 then
		return value + math.floor(-value)
	end
	return value - math.floor(value)
end

--- Rotate a point around the origin
--- @param distance number Distance from origin
--- @param angle number Angle in radians
--- @param center_x number X coordinate of center point
--- @param center_y number Y coordinate of center point
--- @return number x, number y Rotated coordinates
function RotatePoint(distance, angle, center_x, center_y)
	local cos_angle = cos(angle)
	local sin_angle = sin(angle)
	return center_x + distance * cos_angle, center_y + distance * sin_angle
end

--- Calculate squared distance between two points
--- @param x1 number First point X
--- @param y1 number First point Y
--- @param x2 number Second point X
--- @param y2 number Second point Y
--- @return number Squared distance
function DistanceSquared(x1, y1, x2, y2)
	local dx = x2 - x1
	local dy = y2 - y1
	return dx * dx + dy * dy
end

--- Ensure alpha value is in valid range (0-255)
--- @param alpha number|nil The alpha value
--- @return number Valid alpha value
function ValidateAlpha(alpha)
	return Clamp(alpha or 0, 0, 255)
end

--- Update or add a radar target with smoothing
--- @param targets table Array of tracked targets
--- @param distance number Distance to target
--- @param angle number Angle to target in radians
--- @param is_airborne boolean Whether target is airborne
--- @param ship_x number Ship X position
--- @param ship_y number Ship Y position
function UpdateOrAddTarget(targets, distance, angle, is_airborne, ship_x, ship_y)
	if not distance or distance <= MIN_DETECTION_DISTANCE then
		return
	end
	
	-- Calculate target position
	local target_x, target_y = RotatePoint(distance, angle, ship_x, ship_y)
	
	-- Try to find existing nearby target
	local best_match_index = nil
	local best_match_distance = MIN_MATCHING_DISTANCE
	
	for i = 1, #targets do
		local target = targets[i]
		if target.isAirborne == is_airborne then
			local existing_x, existing_y = RotatePoint(target.distance, target.angle, ship_x, ship_y)
			local dist_sq = DistanceSquared(target_x, target_y, existing_x, existing_y)
			
			if dist_sq < best_match_distance then
				best_match_distance = dist_sq
				best_match_index = i
			end
		end
	end
	
	-- Update existing target with smoothing
	if best_match_index then
		local target = targets[best_match_index]
		target.distance = target.distance * SMOOTHING_OLD + distance * SMOOTHING_NEW
		target.angle = target.angle * SMOOTHING_OLD + angle * SMOOTHING_NEW
		target.timeLeft = TARGET_TIMEOUT
		return
	end
	
	-- Add new target (circular buffer behavior)
	if #targets < MAX_TARGETS then
		targets[#targets + 1] = {
			distance = distance,
			angle = angle,
			timeLeft = TARGET_TIMEOUT,
			isAirborne = is_airborne
		}
	else
		targets[NEXT_TARGET_INDEX] = {
			distance = distance,
			angle = angle,
			timeLeft = TARGET_TIMEOUT,
			isAirborne = is_airborne
		}
		NEXT_TARGET_INDEX = NEXT_TARGET_INDEX % MAX_TARGETS + 1
	end
end

--- Process radar inputs and update tracked targets
--- @param targets table Array of tracked targets
--- @param ship_x number Ship X position
--- @param ship_y number Ship Y position
--- @param radar_angle number Current radar sweep angle
--- @param radar_enabled boolean Whether radar is active
function ProcessRadarInputs(targets, ship_x, ship_y, radar_angle, radar_enabled)
	if radar_enabled then
		-- Radar input configuration: button, distance channel, airborne flag
		local radar_inputs = {
			{button = 1, number = 1, airborneFlag = 21},
			{button = 2, number = 5, airborneFlag = 22},
			{button = 19, number = 4, airborneFlag = 20},
			{button = 30, number = 8, airborneFlag = 23},
			{button = 27, number = 26, airborneFlag = 24},
			{button = 26, number = 27, airborneFlag = 25}
		}
		
		for i = 1, #radar_inputs do
			local input_config = radar_inputs[i]
			if getBool(input_config.button) then
				local distance = getNumber(input_config.number)
				if distance and distance > MIN_DETECTION_DISTANCE then
					UpdateOrAddTarget(
						targets,
						distance,
						radar_angle,
						getBool(input_config.airborneFlag),
						ship_x,
						ship_y
					)
				end
			end
		end
	end
	
	-- Remove expired targets
	for i = #targets, 1, -1 do
		local target = targets[i]
		target.timeLeft = target.timeLeft - 1
		if target.timeLeft <= 0 then
			table.remove(targets, i)
		end
	end
end

--- Draw a single radar target
--- @param target table Target data
function DrawTarget(target)
	local target_x, target_y = RotatePoint(target.distance, target.angle, SHIP_GPS_X, SHIP_GPS_Y)
	local screen_x, screen_y = mapToScreen(SHIP_GPS_X, SHIP_GPS_Y, ZOOM, SCREEN_WIDTH, SCREEN_HEIGHT, target_x, target_y)
	
	-- Color: green for airborne targets, blue for surface targets
	local red = 0
	local green = target.isAirborne and 255 or 0
	local blue = target.isAirborne and 0 or 255
	local alpha = ValidateAlpha(target.timeLeft)
	
	screen.setColor(red, green, blue, alpha)
	drawCircleF(screen_x, screen_y, 1.5)
end

--- Draw a labeled point on the map
--- @param world_x number World X coordinate
--- @param world_y number World Y coordinate
--- @param label string Text label
--- @param color table RGBA color {r, g, b, a}
--- @param use_rect boolean Draw rectangle instead of circle
function DrawLabeledPoint(world_x, world_y, label, color, use_rect)
	if world_x == 0 or world_y == 0 then
		return
	end
	
	local screen_x, screen_y = mapToScreen(SHIP_GPS_X, SHIP_GPS_Y, ZOOM, SCREEN_WIDTH, SCREEN_HEIGHT, world_x, world_y)
	screen.setColor(color[1], color[2], color[3], color[4])
	
	if use_rect then
		screen.drawRectF(screen_x - 2, screen_y - 1, 3, 3)
	else
		drawCircleF(screen_x, screen_y, 2)
	end
	
	screen.drawRect(screen_x - 4, screen_y - 4, 6, 6)
	screen.drawText(screen_x + 6, screen_y + (use_rect and 3 or -5), label)
end

--- Check if a point is inside a rectangle
--- @param px number Point X
--- @param py number Point Y
--- @param rx number Rectangle X
--- @param ry number Rectangle Y
--- @param rw number Rectangle width
--- @param rh number Rectangle height
--- @return boolean True if point is inside rectangle
function IsPointInRectangle(px, py, rx, ry, rw, rh)
	return px > rx and py > ry and px < rx + rw and py < ry + rh
end

-- Main Game Loop Functions

function onTick()
	-- Read weapon system positions
	SAM_GPS_X = getNumber(20)
	SAM_GPS_Y = getNumber(21)
	GUN_GPS_X = getNumber(22)
	GUN_GPS_Y = getNumber(23)
	SSM_GPS_X = getNumber(24)
	SSM_GPS_Y = getNumber(25)
	
	-- Read ship position and orientation
	COMPASS_INPUT = getNumber(28)
	SHIP_GPS_X = getNumber(31)
	SHIP_GPS_Y = getNumber(32)
	
	-- Calculate radar sweep angle
	local compass_value = getNumber(30)
	RADAR_ANGLE = (Frac(compass_value) - COMPASS_INPUT - 0.25) * -6.28
	RADAR_ENABLED = getBool(31)
	
	-- Read touch input
	TOUCH_X = getNumber(6)
	TOUCH_Y = getNumber(7)
	TOUCH_ACTIVE = getBool(13)
	
	-- Read ship telemetry
	SHIP_SPEED = getNumber(2)
	RWR_WARNING = getBool(14)
	
	-- Calculate heading in degrees
	SHIP_HEADING_DEGREES = (-COMPASS_INPUT * 360 + 360) % 360
	
	-- Handle UI button clicks
	local zoom_in_button = IsPointInRectangle(TOUCH_X, TOUCH_Y, 0, SCREEN_HEIGHT - 50, 10, 10)
	local zoom_out_button = IsPointInRectangle(TOUCH_X, TOUCH_Y, 0, SCREEN_HEIGHT - 60, 10, 10)
	local reset_button = IsPointInRectangle(TOUCH_X, TOUCH_Y, SCREEN_WIDTH - 30, 0, 30, 10)
	
	if TOUCH_ACTIVE and zoom_in_button then
		ZOOM_IN_CLICKED = true
		ZOOM = ZOOM + 0.15
	else
		ZOOM_IN_CLICKED = false
	end
	
	if TOUCH_ACTIVE and zoom_out_button then
		ZOOM_OUT_CLICKED = true
		ZOOM = ZOOM - 0.15
	else
		ZOOM_OUT_CLICKED = false
	end
	
	if TOUCH_ACTIVE and reset_button then
		RESET_CLICKED = true
	else
		RESET_CLICKED = false
	end
	
	-- Clamp zoom level
	ZOOM = Clamp(ZOOM, ZOOM_MIN, ZOOM_MAX)
	
	-- Update counter for periodic tasks
	UPDATE_COUNTER = UPDATE_COUNTER + 1
	if UPDATE_COUNTER >= UPDATE_INTERVAL then
		UPDATE_COUNTER = UPDATE_INTERVAL
	end
	
	-- Process radar contacts
	ProcessRadarInputs(TRACKED_TARGETS, SHIP_GPS_X, SHIP_GPS_Y, RADAR_ANGLE, RADAR_ENABLED)
	
	-- Output reset button state
	output.setBool(24, RESET_CLICKED)
end

function onDraw()
	-- Get screen dimensions
	SCREEN_WIDTH = screen.getWidth()
	SCREEN_HEIGHT = screen.getHeight()
	
	-- Draw base map
	screen.drawMap(SHIP_GPS_X, SHIP_GPS_Y, ZOOM)
	
	-- Get ship position on screen
	local ship_screen_x, ship_screen_y = mapToScreen(
		SHIP_GPS_X, SHIP_GPS_Y, ZOOM,
		SCREEN_WIDTH, SCREEN_HEIGHT,
		SHIP_GPS_X, SHIP_GPS_Y
	)
	
	-- Draw radar sweep if enabled
	if RADAR_ENABLED then
		-- Calculate radar sweep endpoint
		local radar_end_x, radar_end_y = RotatePoint(RADAR_RANGE, RADAR_ANGLE, SHIP_GPS_X, SHIP_GPS_Y)
		local radar_edge_x, radar_edge_y = RotatePoint(RADAR_RANGE, RADAR_ANGLE + 2000 / RADAR_RANGE, SHIP_GPS_X, SHIP_GPS_Y)
		
		local radar_screen_x, radar_screen_y = mapToScreen(
			SHIP_GPS_X, SHIP_GPS_Y, ZOOM,
			SCREEN_WIDTH, SCREEN_HEIGHT,
			radar_end_x, radar_end_y
		)
		
		-- Calculate radar sweep radius on screen
		local radar_radius = sqrt(DistanceSquared(ship_screen_x, ship_screen_y, radar_screen_x, radar_screen_y))
		
		-- Draw radar sweep circles
		screen.setColor(0, 225, 0, 5)
		drawCircleF(ship_screen_x, ship_screen_y, radar_radius)
		
		screen.setColor(0, 225, 0, 10)
		for i = 0.125, 0.875, 0.125 do
			drawCircle(ship_screen_x, ship_screen_y, radar_radius * i)
		end
		
		-- Draw radar sweep triangle
		local radar_edge_screen_x, radar_edge_screen_y = mapToScreen(
			SHIP_GPS_X, SHIP_GPS_Y, ZOOM,
			SCREEN_WIDTH, SCREEN_HEIGHT,
			radar_edge_x, radar_edge_y
		)
		
		screen.setColor(0, 225, 0, 30)
		screen.drawTriangleF(
			ship_screen_x, ship_screen_y + 1,
			radar_screen_x, radar_screen_y + 2,
			radar_edge_screen_x, radar_edge_screen_y + 3
		)
		
		-- Draw tracked targets
		for i = 1, #TRACKED_TARGETS do
			DrawTarget(TRACKED_TARGETS[i])
		end
	end
	
	-- Draw weapon system positions
	DrawLabeledPoint(SSM_GPS_X, SSM_GPS_Y, "SSM", {100, 100, 0, 220}, false)
	DrawLabeledPoint(GUN_GPS_X, GUN_GPS_Y, "GUN", {0, 225, 0, 50}, true)
	DrawLabeledPoint(SAM_GPS_X, SAM_GPS_Y, "SAM", {0, 225, 0, 50}, true)
	
	-- Draw zoom controls
	screen.setColor(128, 128, 128, 55)
	screen.drawRectF(1, SCREEN_HEIGHT - 60, 7, 20)
	screen.drawRectF(SCREEN_WIDTH - 35, 0, 36, 10)
	
	screen.setColor(0, 0, 0, 150)
	screen.drawTextBox(0, SCREEN_HEIGHT - 60, 10, 10, "+", 0, 0)
	screen.drawTextBox(0, SCREEN_HEIGHT - 50, 10, 10, "-", 0, 0)
	
	-- Draw radar status indicator
	if RADAR_ENABLED then
		screen.drawTextBox(SCREEN_WIDTH - 35, 0, 35, 10, "RADAR", 0, 0)
		screen.setColor(0, 128, 0, 75)
		screen.drawTextBox(SCREEN_WIDTH - 35, 0, 35, 10, "RADAR", 0, 0)
	else
		screen.setColor(128, 0, 0, 75)
		screen.drawTextBox(SCREEN_WIDTH - 35, 0, 35, 10, "RADAR", 0, 0)
	end
	
	-- Draw telemetry panel
	screen.setColor(128, 128, 128, 55)
	screen.drawRectF(0, 0, 42, 35)
	
	screen.setColor(0, 0, 0, 125)
	screen.drawText(1, 29, "RWR ")
	screen.drawText(1, 1, "X ")
	screen.drawText(1, 8, "Y ")
	screen.drawText(1, 15, "SPD ")
	screen.drawText(1, 22, "HDG ")
	
	screen.drawText(1, 1, "  " .. string.format("%.0f", SHIP_GPS_X))
	screen.drawText(1, 8, "  " .. string.format("%.0f", SHIP_GPS_Y))
	screen.drawText(1, 15, "    " .. string.format("%.0f", SHIP_SPEED))
	screen.drawText(1, 22, "    " .. string.format("%.0f", SHIP_HEADING_DEGREES))
	
	-- Draw RWR warning
	if RWR_WARNING then
		screen.setColor(255, 0, 0, 150)
		screen.drawText(1, 29, "    " .. "WARN")
	else
		screen.setColor(0, 0, 0, 55)
		screen.drawText(1, 29, "    " .. "WARN")
	end
	
	-- Draw heading indicator (compass arrow)
	screen.setColor(16, 16, 16, 245)
	local arrow_tip_x = SCREEN_WIDTH / 2 + COMPASS_ARROW_TIP_RADIUS * -sin(COMPASS_INPUT * 2 * pi)
	local arrow_tip_y = SCREEN_HEIGHT / 2 - COMPASS_ARROW_TIP_RADIUS * cos(COMPASS_INPUT * 2 * pi)
	local arrow_left_x = SCREEN_WIDTH / 2 + COMPASS_ARROW_BASE_RADIUS * -sin((COMPASS_INPUT + COMPASS_ARROW_LEFT_OFFSET) * 2 * pi)
	local arrow_left_y = SCREEN_HEIGHT / 2 - COMPASS_ARROW_BASE_RADIUS * cos((COMPASS_INPUT + COMPASS_ARROW_LEFT_OFFSET) * 2 * pi)
	local arrow_right_x = SCREEN_WIDTH / 2 + COMPASS_ARROW_BASE_RADIUS * -sin((COMPASS_INPUT + COMPASS_ARROW_RIGHT_OFFSET) * 2 * pi)
	local arrow_right_y = SCREEN_HEIGHT / 2 - COMPASS_ARROW_BASE_RADIUS * cos((COMPASS_INPUT + COMPASS_ARROW_RIGHT_OFFSET) * 2 * pi)
	
	screen.drawTriangleF(
		arrow_tip_x, arrow_tip_y,
		arrow_left_x, arrow_left_y,
		arrow_right_x, arrow_right_y
	)
end
