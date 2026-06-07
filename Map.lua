BASE_GPS_X = 0
BASE_GPS_Y = 0
BASE_HEADING_ABSOLUTE = 0
RADAR_HEADING_RELATIVE = 0
ZOOM = 0
RADAR_RANGE = 10000

-- Local function caching for performance
local cos = math.cos
local sin = math.sin
local fmod = math.fmod
local ceil = math.ceil
local abs = math.abs
local pi = math.pi
local getNumber = input.getNumber
local setColor = screen.setColor
local drawLine = screen.drawLine
local drawRect = screen.drawRect
local drawText = screen.drawText
local drawMap = screen.drawMap
local mapToScreen = map.mapToScreen
local screenToMap = map.screenToMap
local tostr = tostring

function onTick()
    BASE_GPS_X = getNumber(1)
    BASE_GPS_Y = getNumber(2)
    BASE_HEADING_ABSOLUTE = fmod((getNumber(3) + 1.25) * 2 * pi, 2 * pi)
    RADAR_HEADING_RELATIVE = (-2) * pi * fmod(getNumber(4), 1)
    ZOOM = getNumber(5)
end

function onDraw()
    local w = screen.getWidth()
    local h = screen.getHeight()
    local halfW = w / 2
    local halfH = h / 2

    drawMap(BASE_GPS_X, BASE_GPS_Y, ZOOM)

    setColor(0, 255, 0)
    local mapX, mapY = mapToScreen(BASE_GPS_X, BASE_GPS_Y, ZOOM, w, h, BASE_GPS_X, BASE_GPS_Y)
    drawRect(mapX - 1, mapY + 1, 3, 3)

    local radarScreenRange = RADAR_RANGE / 2 / ZOOM
    local baseAngle = BASE_HEADING_ABSOLUTE + RADAR_HEADING_RELATIVE
    for i = 0, 20 do
        setColor(0, 255, 0, 255 - (i * 255 / 20))
        local angle = baseAngle + (i * pi / 360)
        drawLine(
            halfW, halfH,
            halfW + (radarScreenRange * cos(angle)),
            halfH - (radarScreenRange * sin(angle))
        )
    end

    setColor(0, 0, 0)
    drawLine(
        halfW, halfH,
        halfW + (10 * cos(BASE_HEADING_ABSOLUTE)),
        halfH - (10 * sin(BASE_HEADING_ABSOLUTE))
    )

    local worldX, _ = screenToMap(BASE_GPS_X, BASE_GPS_Y, ZOOM, w, h, halfW + 50, halfH)
    local distance = abs(worldX - BASE_GPS_X)
    setColor(255, 255, 255)
    drawLine(0, h - 13, 50, h - 13)
    drawText(0, h - 8, tostr(ceil(distance / 1000)) .. "km")

end
