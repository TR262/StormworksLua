-- all angles are in radians from east
RADAR_RANGE = 6400

BASE_GPS_X = 0
BASE_GPS_Y = 0
YAW = 0
PITCH = 0
ROLL = 0
ZOOM = 0

TARGETS = {}

-- Local function caching for performance
local cos = math.cos
local sin = math.sin
local sqrt = math.sqrt
local fmod = math.fmod
local ceil = math.ceil
local pi = math.pi
local getNumber = input.getNumber
local getBool = input.getBool
local setColor = screen.setColor
local drawText = screen.drawText
local drawCircle = screen.drawCircle
local mapToScreen = map.mapToScreen
local tblInsert = table.insert
local tblRemove = table.remove
local tostr = tostring

function CreateTarget(x, y, z, distance, lastUpdate)
    return {
        x = x,
        y = y,
        z = z,
        distance = distance,
        lastUpdate = lastUpdate
    }
end

function GPSDistance3D(t1, t2)
    local dx = t1.x - t2.x
    local dy = t1.y - t2.y
    local dz = t1.z - t2.z
    return sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

DELTA = 20
function ProcessNewTarget(newTarget)
    for i = 1, #TARGETS do
        local target = TARGETS[i]
        if (GPSDistance3D(target, newTarget) < DELTA) then
            TARGETS[i] = CreateTarget(
                target.x + ((target.x - newTarget.x) / 10),
                target.y + ((target.y - newTarget.y) / 10),
                target.z + ((target.z - newTarget.z) / 2),
                (target.distance + newTarget.distance) / 2,
                target.lastUpdate - 1
            )
            return
        end
    end
    tblInsert(TARGETS, newTarget)
end

function ConvertToLocalCoordinates(x, y, z)
    -- Cache trig values to avoid computing them 9+ times
    local cosYaw = cos(YAW)
    local sinYaw = sin(YAW)
    local cosPitch = cos(PITCH)
    local sinPitch = sin(PITCH)
    local cosRoll = cos(ROLL)
    local sinRoll = sin(ROLL)

    local rotMatrix = {
        {
            (cosPitch * cosYaw),
            (cosPitch * sinYaw * sinRoll) - (sinPitch * cosRoll),
            (cosPitch * sinYaw * cosRoll) + (sinPitch * sinRoll),
        },
        {
            (sinPitch * cosYaw),
            (sinPitch * sinYaw * sinRoll) + (cosPitch * cosRoll),
            (sinPitch * sinYaw * cosRoll) - (cosPitch * sinRoll),
        },
        {
            (-sinYaw),
            (cosYaw * sinRoll),
            (cosYaw * cosRoll)
        },
    }

    return {
        x = (rotMatrix[1][1] * x) + (rotMatrix[1][2] * y) + (rotMatrix[1][3] * z),
        y = (rotMatrix[2][1] * x) + (rotMatrix[2][2] * y) + (rotMatrix[2][3] * z),
        z = (rotMatrix[3][1] * x) + (rotMatrix[3][2] * y) + (rotMatrix[3][3] * z),
    }
end

TIMEOUT = 60 * 5
function onTick()
    BASE_GPS_X = getNumber(27)
    BASE_GPS_Y = getNumber(28)
    YAW = fmod((getNumber(29) + 1.25) * 2 * pi, 2 * pi)
    PITCH = getNumber(30) * 2 * pi
    ROLL = getNumber(31) * 2 * pi
    ZOOM = getNumber(32)

    for i = 1, 5 do
        if (getBool(i)) then
            local distance = getNumber((i * 4) - 3)
            local azimuth = (pi / 2) + (2 * pi * getNumber((i * 4) - 2))
            local elevation = (pi / 2) + (pi * getNumber((i * 4) - 1))

            -- convert xyz from polar coordinates
            local cosAz = cos(azimuth)
            local sinAz = sin(azimuth)
            local cosEl = cos(elevation)
            local sinEl = sin(elevation)
            local x = distance * cosAz * cosEl
            local y = distance * sinAz * cosEl
            local z = distance * sinEl

            local localXYZ = ConvertToLocalCoordinates(x, y, z)

            async.httpGet(6942, "/INFO?x=" .. tostr(x)
                .. "&y=" .. tostr(y)
                .. "&z=" .. tostr(z)
                .. "&localX=" .. tostr(localXYZ.x)
                .. "&localY=" .. tostr(localXYZ.y)
                .. "&localZ=" .. tostr(localXYZ.z)
                .. "&distance=" .. tostr(distance)
                .. "&azimuth=" .. tostr(azimuth)
                .. "&elevation=" .. tostr(elevation)
                .. "&yaw=" .. tostr(YAW)
                .. "&pitch=" .. tostr(PITCH)
                .. "&roll=" .. tostr(ROLL)
                .. "&zoom=" .. tostr(ZOOM)
            )

            ProcessNewTarget(CreateTarget(
                localXYZ.x + BASE_GPS_X,
                localXYZ.y + BASE_GPS_Y,
                localXYZ.z,
                distance,
                0
            ))
        else
            break
        end
    end

    -- Iterate backwards to safely remove while iterating
    for i = #TARGETS, 1, -1 do
        local target = TARGETS[i]
        if (target.lastUpdate > TIMEOUT) then
            tblRemove(TARGETS, i)
        else
            TARGETS[i].lastUpdate = target.lastUpdate + 1
        end
    end
end

function onDraw()
    local w = screen.getWidth()
    local h = screen.getHeight()

    setColor(255, 255, 255)
    drawText(0, 0, "ZOOM: " .. tostr(ceil(ZOOM)))
    drawText(0, 8, "TRACKING " .. tostr(#TARGETS) .. " TANGOS")
    local maxDistance = 0
    for i = 1, #TARGETS do
        local target = TARGETS[i]
        if (target.distance > maxDistance) then
            maxDistance = target.distance
        end
    end
    drawText(0, 16, "MAX DISTANCE: " .. tostr(ceil(maxDistance)) .. "m")
    drawText(w / 2, 4, "N")
    drawText(w / 2, h - 8, "S")
    drawText(4, h / 2, "W")
    drawText(w - 8, h / 2, "E")

    for i = 1, #TARGETS do
        local target = TARGETS[i]
        local mapX, mapY = mapToScreen(BASE_GPS_X, BASE_GPS_Y, ZOOM, w, h, target.x, target.y)
        setColor(255, 0, 0)
        drawCircle(mapX, mapY, 1)
    end
end
