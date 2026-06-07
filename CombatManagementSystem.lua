-- ============================================================
-- Combat Management System (CMS) - Stormworks Lua Microcontroller
-- Displays radar targets, weapon markers, and ship info on a map
-- ============================================================

-- === CONFIGURATION CONSTANTS ===
MAX_TARGETS = 128
RADAR_RANGE = 16666
PROXIMITY_THRESHOLD = 150
MIN_DISTANCE = 5
MIN_ZOOM = 1
MAX_ZOOM = 50
TARGET_LIFETIME = 310
SMOOTHING_WEIGHT_OLD = 0.3
SMOOTHING_WEIGHT_NEW = 0.7
MAX_TICK_COUNTER = 30
COMPASS_OUTER_RADIUS = 7
COMPASS_INNER_RADIUS = 5
COMPASS_WING_LEFT_FACTOR = 0.4
COMPASS_WING_RIGHT_FACTOR = 0.6
COMPASS_LEFT_ANGLE = COMPASS_WING_LEFT_FACTOR * 2 * math.pi
COMPASS_RIGHT_ANGLE = COMPASS_WING_RIGHT_FACTOR * 2 * math.pi
RADAR_CONE_OFFSET = 2000

-- Marker colors: {R, G, B, A}
COLOR_SSM = {100, 100, 0, 220}
COLOR_GUN = {0, 225, 0, 50}
COLOR_SAM = {0, 225, 0, 50}

-- Radar input channel definitions
-- Each entry maps a button channel, distance channel, and airborne flag channel
RADAR_INPUTS = {
	{button = 1,  number = 1,  airborneFlag = 21},
	{button = 2,  number = 5,  airborneFlag = 22},
	{button = 19, number = 4,  airborneFlag = 20},
	{button = 30, number = 8,  airborneFlag = 23},
	{button = 27, number = 26, airborneFlag = 24},
	{button = 26, number = 27, airborneFlag = 25},
}

-- === STATE VARIABLES ===
targets = {}
targetOverwriteIndex = 1
screenWidth = 0
screenHeight = 0
zoom = 50
isZoomingIn = false
isZoomingOut = false
radarTogglePressed = false
tickCounter = 0
gpsX = 0
gpsY = 0
unusedVar = 0
samX = 0
samY = 0
gunX = 0
gunY = 0
ssmX = 0
ssmY = 0
compassHeading = 0
radarAngle = 0
radarActive = false
touchX = 0
touchY = 0
isTouching = false
speed = 0
headingDegrees = 0
rwrWarning = false

-- === LOCAL FUNCTION REFERENCES (performance optimization) ===
local cos = math.cos
local sin = math.sin
local sqrt = math.sqrt
local pi = math.pi
local mapToScreen = map.mapToScreen
local getNumber = input.getNumber
local getBool = input.getBool
local drawCircle = screen.drawCircle
local drawCircleF = screen.drawCircleF

-- ============================================================
-- UTILITY FUNCTIONS
-- ============================================================

--- Clamps a value between min and max
function clamp(value, min, max)
	return value < min and min or (value > max and max or value)
end

--- Returns the fractional part of a number (always positive)
function fractionalPart(value)
	if value < 0 then
		return value + math.floor(-value)
	end
	return value - math.floor(value)
end

--- Converts polar coordinates to cartesian, offset from an origin
function polarToCartesian(distance, angle, originX, originY)
	local cosAngle = cos(angle)
	local sinAngle = sin(angle)
	return originX + distance * cosAngle, originY + distance * sinAngle
end

--- Returns the squared distance between two points
function distanceSquared(x1, y1, x2, y2)
	local dx = x2 - x1
	local dy = y2 - y1
	return dx * dx + dy * dy
end

--- Clamps an alpha value to the valid range [0, 255]
function clampAlpha(value)
	return clamp(value or 0, 0, 255)
end

-- ============================================================
-- RADAR TARGET MANAGEMENT
-- ============================================================

--- Processes a new radar contact, either merging with an existing target or adding a new one
function processRadarContact(targetList, distance, angle, isAirborne, originX, originY)
	if not distance or distance <= MIN_DISTANCE then
		return
	end

	local cosAngle = cos(angle)
	local sinAngle = sin(angle)
	local contactWorldX = originX + distance * cosAngle
	local contactWorldY = originY + distance * sinAngle

	local closestIndex = nil
	local closestDistSq = PROXIMITY_THRESHOLD

	-- Search for an existing target close to this contact
	for idx = 1, #targetList do
		local target = targetList[idx]
		if target.isAirborne == isAirborne then
			local targetCos = cos(target.angle)
			local targetSin = sin(target.angle)
			local targetWorldX = originX + target.distance * targetCos
			local targetWorldY = originY + target.distance * targetSin
			local dx = targetWorldX - contactWorldX
			local dy = targetWorldY - contactWorldY
			local distSq = dx * dx + dy * dy
			if distSq < closestDistSq then
				closestDistSq = distSq
				closestIndex = idx
			end
		end
	end

	-- If a nearby target exists, smooth-merge the new data into it
	if closestIndex then
		local target = targetList[closestIndex]
		target.distance = target.distance * SMOOTHING_WEIGHT_OLD + distance * SMOOTHING_WEIGHT_NEW
		target.angle = target.angle * SMOOTHING_WEIGHT_OLD + angle * SMOOTHING_WEIGHT_NEW
		target.timeLeft = TARGET_LIFETIME
		return
	end

	-- Otherwise, add a new target (overwrite oldest if at capacity)
	if #targetList < MAX_TARGETS then
		targetList[#targetList + 1] = {distance = distance, angle = angle, timeLeft = TARGET_LIFETIME, isAirborne = isAirborne}
	else
		targetList[targetOverwriteIndex] = {distance = distance, angle = angle, timeLeft = TARGET_LIFETIME, isAirborne = isAirborne}
		targetOverwriteIndex = targetOverwriteIndex % MAX_TARGETS + 1
	end
end

--- Updates all targets: reads new radar contacts and ages/removes old ones
function updateTargets(targetList, originX, originY, currentRadarAngle, isRadarActive)
	-- Read new radar contacts from input channels
	if isRadarActive then
		for idx = 1, #RADAR_INPUTS do
			local inputDef = RADAR_INPUTS[idx]
			if getBool(inputDef.button) then
				local distance = getNumber(inputDef.number)
				if distance and distance > MIN_DISTANCE then
					processRadarContact(targetList, distance, currentRadarAngle, getBool(inputDef.airborneFlag), originX, originY)
				end
			end
		end
	end

	-- Age targets and remove expired ones
	for idx = #targetList, 1, -1 do
		local target = targetList[idx]
		target.timeLeft = target.timeLeft - 1
		if target.timeLeft <= 0 then
			table.remove(targetList, idx)
		end
	end
end

-- ============================================================
-- DRAWING HELPER FUNCTIONS
-- ============================================================

--- Draws a single radar target blip on the map
function drawTargetBlip(target)
	local worldX, worldY = polarToCartesian(target.distance, target.angle, gpsX, gpsY)
	local pixelX, pixelY = mapToScreen(gpsX, gpsY, zoom, screenWidth, screenHeight, worldX, worldY)
	local colorRed = 0
	local colorGreen = target.isAirborne and 255 or 0
	local colorBlue = target.isAirborne and 0 or 255
	local alpha = clampAlpha(target.timeLeft)
	screen.setColor(colorRed, colorGreen, colorBlue, alpha)
	drawCircleF(pixelX, pixelY, 1.5)
end

--- Draws a weapon/target marker on the map with a label
function drawMarker(worldX, worldY, label, color, isSquareMarker)
	if worldX == 0 or worldY == 0 then
		return
	end
	local pixelX, pixelY = mapToScreen(gpsX, gpsY, zoom, screenWidth, screenHeight, worldX, worldY)
	screen.setColor(color[1], color[2], color[3], color[4])
	if isSquareMarker then
		screen.drawRectF(pixelX - 2, pixelY - 1, 3, 3)
	else
		drawCircleF(pixelX, pixelY, 2)
	end
	screen.drawRect(pixelX - 4, pixelY - 4, 6, 6)
	screen.drawText(pixelX + 6, pixelY + (isSquareMarker and 3 or -5), label)
end

--- Checks if a point is inside a rectangle
function isPointInRect(pointX, pointY, rectX, rectY, rectWidth, rectHeight)
	return pointX > rectX and pointY > rectY and pointX < rectX + rectWidth and pointY < rectY + rectHeight
end

-- ============================================================
-- MAIN TICK FUNCTION
-- ============================================================

function onTick()
	-- Read weapon target positions
	samX = getNumber(20)
	samY = getNumber(21)
	gunX = getNumber(22)
	gunY = getNumber(23)
	ssmX = getNumber(24)
	ssmY = getNumber(25)

	-- Read navigation data
	compassHeading = getNumber(28)
	gpsX = getNumber(31)
	gpsY = getNumber(32)

	-- Calculate radar angle from heading
	local rawHeading = getNumber(30)
	local headingFraction = rawHeading < 0 and rawHeading + math.floor(-rawHeading) or rawHeading - math.floor(rawHeading)
	radarAngle = (headingFraction - compassHeading - 0.25) * -6.28

	-- Read radar state
	radarActive = getBool(31)

	-- Read touch input
	touchX = getNumber(6)
	touchY = getNumber(7)
	isTouching = getBool(13)

	-- Read speed and RWR
	speed = getNumber(2)
	rwrWarning = getBool(14)
	headingDegrees = (-compassHeading * 360 + 360) % 360

	-- Handle zoom in button (bottom-left area)
	local zoomInPressed = touchX > 0 and touchY > screenHeight - 50 and touchX < 10 and touchY < screenHeight - 40
	local zoomOutPressed = touchX > 0 and touchY > screenHeight - 60 and touchX < 10 and touchY < screenHeight - 50
	local radarBtnPressed = touchX > screenWidth - 30 and touchY > 0 and touchX < screenWidth and touchY < 10

	if isTouching and zoomInPressed then
		isZoomingIn = true
		zoom = zoom + 0.15
	else
		isZoomingIn = false
	end

	if isTouching and zoomOutPressed then
		isZoomingOut = true
		zoom = zoom - 0.15
	else
		isZoomingOut = false
	end

	if isTouching and radarBtnPressed then
		radarTogglePressed = true
	else
		radarTogglePressed = false
	end

	-- Clamp zoom
	if zoom < MIN_ZOOM then
		zoom = MIN_ZOOM
	elseif zoom > MAX_ZOOM then
		zoom = MAX_ZOOM
	end

	-- Tick counter (used for timing)
	tickCounter = tickCounter + 1
	if tickCounter >= MAX_TICK_COUNTER then
		tickCounter = MAX_TICK_COUNTER
	end

	-- Update radar targets
	updateTargets(targets, gpsX, gpsY, radarAngle, radarActive)

	-- Output radar toggle state
	output.setBool(24, radarTogglePressed)
end

-- ============================================================
-- MAIN DRAW FUNCTION
-- ============================================================

function onDraw()
	screenWidth = screen.getWidth()
	screenHeight = screen.getHeight()

	-- Draw the map background
	screen.drawMap(gpsX, gpsY, zoom)

	-- Get ship's position on screen
	local centerPixelX, centerPixelY = mapToScreen(gpsX, gpsY, zoom, screenWidth, screenHeight, gpsX, gpsY)

	-- === RADAR DISPLAY ===
	if radarActive then
		-- Calculate radar sweep line endpoint
		local radarCos = cos(radarAngle)
		local radarSin = sin(radarAngle)
		local radarEndWorldX = gpsX + RADAR_RANGE * radarCos
		local radarEndWorldY = gpsY + RADAR_RANGE * radarSin

		-- Calculate radar cone edge
		local coneAngle = radarAngle + RADAR_CONE_OFFSET / RADAR_RANGE
		local coneEndWorldX = gpsX + RADAR_RANGE * cos(coneAngle)
		local coneEndWorldY = gpsY + RADAR_RANGE * sin(coneAngle)

		-- Convert radar endpoint to screen coordinates for radius calculation
		local radarEndPixelX, radarEndPixelY = mapToScreen(gpsX, gpsY, zoom, screenWidth, screenHeight, radarEndWorldX, radarEndWorldY)
		local deltaX = radarEndPixelX - centerPixelX
		local deltaY = radarEndPixelY - centerPixelY
		local radarPixelRadius = sqrt(deltaX * deltaX + deltaY * deltaY)

		-- Draw filled radar circle
		screen.setColor(0, 225, 0, 5)
		drawCircleF(centerPixelX, centerPixelY, radarPixelRadius)

		-- Draw range rings
		screen.setColor(0, 225, 0, 10)
		for fraction = 0.125, 0.875, 0.125 do
			drawCircle(centerPixelX, centerPixelY, radarPixelRadius * fraction)
		end

		-- Draw radar sweep cone
		local conePixelX, conePixelY = mapToScreen(gpsX, gpsY, zoom, screenWidth, screenHeight, coneEndWorldX, coneEndWorldY)
		screen.setColor(0, 225, 0, 30)
		screen.drawTriangleF(centerPixelX, centerPixelY + 1, radarEndPixelX, radarEndPixelY + 2, conePixelX, conePixelY + 3)

		-- Draw all radar targets
		for idx = 1, #targets do
			local target = targets[idx]
			local targetCos = cos(target.angle)
			local targetSin = sin(target.angle)
			local targetWorldX = gpsX + target.distance * targetCos
			local targetWorldY = gpsY + target.distance * targetSin
			local targetPixelX, targetPixelY = mapToScreen(gpsX, gpsY, zoom, screenWidth, screenHeight, targetWorldX, targetWorldY)

			local colorGreen = target.isAirborne and 255 or 0
			local colorBlue = target.isAirborne and 0 or 255
			local alpha = target.timeLeft
			if alpha < 0 then
				alpha = 0
			elseif alpha > 255 then
				alpha = 255
			end

			screen.setColor(0, colorGreen, colorBlue, alpha)
			drawCircleF(targetPixelX, targetPixelY, 1.5)
		end
	end

	-- === WEAPON TARGET MARKERS ===
	-- SSM (Ship-to-Ship Missile) marker
	if ssmX ~= 0 and ssmY ~= 0 then
		local pixelX, pixelY = mapToScreen(gpsX, gpsY, zoom, screenWidth, screenHeight, ssmX, ssmY)
		screen.setColor(100, 100, 0, 220)
		drawCircleF(pixelX, pixelY, 2)
		screen.drawRect(pixelX - 4, pixelY - 4, 6, 6)
		screen.drawText(pixelX + 6, pixelY - 5, "SSM")
	end

	-- GUN marker
	if gunX ~= 0 and gunY ~= 0 then
		local pixelX, pixelY = mapToScreen(gpsX, gpsY, zoom, screenWidth, screenHeight, gunX, gunY)
		screen.setColor(0, 225, 0, 50)
		screen.drawRectF(pixelX - 2, pixelY - 1, 3, 3)
		screen.drawRect(pixelX - 4, pixelY - 4, 6, 6)
		screen.drawText(pixelX + 6, pixelY + 3, "GUN")
	end

	-- SAM (Surface-to-Air Missile) marker
	if samX ~= 0 and samY ~= 0 then
		local pixelX, pixelY = mapToScreen(gpsX, gpsY, zoom, screenWidth, screenHeight, samX, samY)
		screen.setColor(0, 225, 0, 50)
		screen.drawRectF(pixelX - 2, pixelY - 1, 3, 3)
		screen.drawRect(pixelX - 4, pixelY - 4, 6, 6)
		screen.drawText(pixelX + 6, pixelY + 3, "SAM")
	end

	-- === UI BUTTONS ===
	-- Zoom +/- buttons (bottom left)
	screen.setColor(128, 128, 128, 55)
	screen.drawRectF(1, screenHeight - 60, 7, 20)
	screen.drawRectF(screenWidth - 35, 0, 36, 10)

	screen.setColor(0, 0, 0, 150)
	screen.drawTextBox(0, screenHeight - 60, 10, 10, "+", 0, 0)
	screen.drawTextBox(0, screenHeight - 50, 10, 10, "-", 0, 0)

	-- Radar status indicator (top right)
	if radarActive then
		screen.drawTextBox(screenWidth - 35, 0, 35, 10, "RADAR", 0, 0)
		screen.setColor(0, 128, 0, 75)
		screen.drawTextBox(screenWidth - 35, 0, 35, 10, "RADAR", 0, 0)
	else
		screen.setColor(128, 0, 0, 75)
		screen.drawTextBox(screenWidth - 35, 0, 35, 10, "RADAR", 0, 0)
	end

	-- === INFO PANEL (top left) ===
	screen.setColor(128, 128, 128, 55)
	screen.drawRectF(0, 0, 42, 35)

	screen.setColor(0, 0, 0, 125)
	screen.drawText(1, 29, "RWR ")
	screen.drawText(1, 1, "X ")
	screen.drawText(1, 8, "Y ")
	screen.drawText(1, 15, "SPD ")
	screen.drawText(1, 22, "HDG ")
	screen.drawText(1, 1, "  " .. string.format("%.0f", gpsX))
	screen.drawText(1, 8, "  " .. string.format("%.0f", gpsY))
	screen.drawText(1, 15, "    " .. string.format("%.0f", speed))
	screen.drawText(1, 22, "    " .. string.format("%.0f", headingDegrees))

	-- RWR warning indicator
	if rwrWarning then
		screen.setColor(255, 0, 0, 150)
		screen.drawText(1, 29, "    " .. "WARN")
	else
		screen.setColor(0, 0, 0, 55)
		screen.drawText(1, 29, "    " .. "WARN")
	end

	-- === COMPASS / SHIP HEADING INDICATOR (center) ===
	screen.setColor(16, 16, 16, 245)
	local headingAngle = compassHeading * 2 * pi
	local compassTipX = screenWidth / 2 + COMPASS_OUTER_RADIUS * -sin(headingAngle)
	local compassTipY = screenHeight / 2 - COMPASS_OUTER_RADIUS * cos(headingAngle)
	local compassLeftX = screenWidth / 2 + COMPASS_INNER_RADIUS * -sin(headingAngle + COMPASS_LEFT_ANGLE)
	local compassLeftY = screenHeight / 2 - COMPASS_INNER_RADIUS * cos(headingAngle + COMPASS_LEFT_ANGLE)
	local compassRightX = screenWidth / 2 + COMPASS_INNER_RADIUS * -sin(headingAngle + COMPASS_RIGHT_ANGLE)
	local compassRightY = screenHeight / 2 - COMPASS_INNER_RADIUS * cos(headingAngle + COMPASS_RIGHT_ANGLE)
	screen.drawTriangleF(compassTipX, compassTipY, compassLeftX, compassLeftY, compassRightX, compassRightY)
end
