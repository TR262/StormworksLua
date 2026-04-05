-- Turret Aiming Controller
-- Reads GPS target data and outputs yaw/pitch servo angles with ballistic prediction.
--
-- Input composite channels:
--   Number 1  : own GPS X
--   Number 2  : own GPS Y
--   Number 3  : own altitude (Z)
--   Number 4  : own yaw (0–1 rotation fraction, 0 = north)
--   Number 5  : target GPS X
--   Number 6  : target GPS Y
--   Number 7  : target altitude
--   Bool 1    : target active / lock
--   Bool rest : weapon reloaded  (channel index set via "reload state" property)
--
-- Output composite channels:
--   Number 1  : yaw servo command   (-0.5 to 0.5)
--   Number 2  : pitch servo command (-0.5 to 0.5)
--   Bool 1    : fire trigger

ft=0 Eangle=0 ySGPSx=0 ySGPSy=0 ySalt=0 G=-30/3600 ttdy=0 aimt=0
iN=input.getNumber
iB=input.getBool
oN=output.setNumber
oB=output.setBool
pgN=property.getNumber
pgB=property.getBool
lmax=pgN("max turn left (deg)")/360
rmax=-pgN("max turn right (deg)")/360
umax=pgN("max turn up (deg)")/360
dmax=-pgN("max turn down (deg)")/360
vpm=pgN("yaw pivot")
rest=pgN("reload state")
spmu=pgN("Aim speed")
usdg=pgB("turret upside down")
ACY=pgN("accuracy")/1000
Delay=7.5 FOV=0.014 NP=0

M=math
abs=M.abs
sin=M.sin
cos=M.cos
tan=M.tan
asin=M.asin
atan=M.atan
sqrt=M.sqrt
pi2=M.pi*2
pi=M.pi
log=M.log
fmod=M.fmod
floor=M.floor
Delay=9

wtyp=pgN('Weapon Type')
bal={{800,0.025,120},{1000,0.02,150},{1000,0.01,300},{900,0.005,600},{800,0.002,1500},{700,0.001,2400},{600,0.0005,2400}}
wtyp=wtyp<1 and 1 or wtyp>#bal and #bal or wtyp
velo=bal[wtyp][1]
DRAG=bal[wtyp][2]
lifes=bal[wtyp][3]

-- Returns true when x lies within the closed interval [y-z, y+z].
function th(x,y,z)
    return x>=y-z and x<=y+z
end

-- Clamps v to the range [mn, mx].
function clamp(v,mn,mx)
    return v<mn and mn or v>mx and mx or v
end

-- Normalises a rotation value to the range (-0.5, 0.5].
function nr(a)
    a=fmod(a,1)
    return a>0.5 and a-1 or a<-0.5 and a+1 or a
end

-- Distance (metres) covered by a projectile in t ticks given launch velocity v0
-- and per-tick drag coefficient D (velocity is multiplied by (1-D) each tick).
function pd(v0,D,t)
    if D==0 then return v0*t end
    return v0*(1-(1-D)^t)/D
end

-- Iterative time-of-flight estimate: finds t such that pd(velo,DRAG,t) ≈ d.
function tof_est(d)
    local t=d/velo
    for _=1,3 do
        local dd=pd(velo,DRAG,t)
        if dd==0 then break end
        t=t*d/dd
    end
    return t
end

-- Persistent state
cYaw=0 cPit=0   -- current servo positions (slew-rate limited)
ptx=0 pty=0 ptz=0   -- previous target position (for velocity estimation)
tvx=0 tvy=0 tvz=0   -- estimated target velocity (metres/tick)

function onTick()
    ft=ft+1

    -- Own stabilised GPS position
    ySGPSx=iN(1)
    ySGPSy=iN(2)
    ySalt =iN(3)
    local oYaw=iN(4)    -- own vehicle yaw (0-1 rotation fraction)

    -- Target data
    local tAct=iB(1)            -- target lock active
    local tx=iN(5)              -- target GPS X
    local ty=iN(6)              -- target GPS Y
    local tz=iN(7)              -- target altitude
    local rld=iB(floor(rest))   -- weapon reloaded signal

    if tAct then
        -- Update velocity estimate from position delta.
        -- NP==0 on first active tick: seed previous position to avoid a spike.
        if NP==0 then
            ptx=tx pty=ty ptz=tz
            tvx=0  tvy=0  tvz=0
            NP=1
        else
            tvx=tx-ptx tvy=ty-pty tvz=tz-ptz
            ptx=tx pty=ty ptz=tz
        end

        -- Displacement to target
        local dx=tx-ySGPSx
        local dy=ty-ySGPSy
        local dz=tz-ySalt
        local dist=sqrt(dx*dx+dy*dy+dz*dz)

        -- First-pass time-of-flight, then refine with lead position
        local t1=tof_est(dist)
        local lx=tx+tvx*t1-ySGPSx
        local ly=ty+tvy*t1-ySGPSy
        local lz=tz+tvz*t1-ySalt
        local t2=tof_est(sqrt(lx*lx+ly*ly+lz*lz))

        -- Final lead-compensated displacement
        lx=tx+tvx*t2-ySGPSx
        ly=ty+tvy*t2-ySGPSy
        lz=tz+tvz*t2-ySalt

        -- Gravity drop compensation: aim high by ½·|G|·t²
        -- (G is negative, so subtracting G·t² adds the upward correction)
        lz=lz-0.5*G*t2*t2

        -- Desired angles in rotation units
        local tYaw=atan(lx,ly)/pi2+vpm
        local hd=sqrt(lx*lx+ly*ly)
        Eangle=-atan(lz,hd)/pi2

        -- Yaw relative to own vehicle heading
        local rYaw=nr(tYaw-oYaw)

        -- Handle upside-down mounting
        if usdg then
            rYaw=nr(rYaw+0.5)
            Eangle=-Eangle
        end

        -- Clamp to mechanical limits
        rYaw  =clamp(rYaw,  rmax,lmax)
        Eangle=clamp(Eangle,dmax,umax)

        -- Slew-rate limiting: move toward target angle by at most spmu per tick
        local dY=nr(rYaw-cYaw)
        local dP=Eangle-cPit
        if abs(dY)>spmu then dY=dY>0 and spmu or -spmu end
        if abs(dP)>spmu then dP=dP>0 and spmu or -spmu end
        cYaw=nr(cYaw+dY)
        cPit=cPit+dP

        oN(1,cYaw)
        oN(2,cPit)
        ttdy=dP

        -- Fire when servo has reached aim point within accuracy tolerance, and reloaded
        local aimed=th(cYaw,rYaw,ACY) and th(cPit,Eangle,ACY)
        if aimed then aimt=aimt+1 else aimt=0 end
        oB(1,rld and aimt>=Delay)
    else
        -- Target lost: reset velocity and aim timer; slew back toward neutral
        NP=0
        tvx=0 tvy=0 tvz=0
        aimt=0 ttdy=0

        local dY=nr(0-cYaw)
        local dP=0-cPit
        if abs(dY)>spmu then dY=dY>0 and spmu or -spmu end
        if abs(dP)>spmu then dP=dP>0 and spmu or -spmu end
        cYaw=nr(cYaw+dY)
        cPit=cPit+dP

        oN(1,cYaw)
        oN(2,cPit)
        oB(1,false)
    end
end
