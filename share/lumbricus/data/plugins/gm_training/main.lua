local trainee -- a TeamMember
local target_class
local target -- sprite for current target
local timer_target -- timeout for hitting the target
local timer_check
local winstate -- nil: ongoing, false: lost, true: won
local targets_left -- number of targets that must be still hit
local timer_limit
local scenario -- current program
local onend

-- sc = scenario, see program.lua
-- endcallback = function called when user has won or lost
function start_training(sc, endcallback)
    killAll()
    scenario = sc
    onend = endcallback
    cospawn(initthread)
end

function init()
    -- create the thing the worm is going to shoot
    target_class = createSpriteClass {
        name = "x_target",
        initPhysic = relay {
            collisionID = "projectile_self",
            radius = 25,
            mass = 1/0, --inf
        },
        initNoActivity = true,
        sequenceType = "s_target",
    }
    addSpriteClassEvent(target_class, "sprite_impact", targetHit)
    addSpriteClassEvent(target_class, "sprite_die", targetKill)
end

function initthread()
    -- there should be exactly 1 team/member
    trainee = assert(Control:teams()[1]:members()[1])
    -- give some weapons... training should go from simple to stronger weapons,
    local ws = trainee:team():weapons()
    -- remove all weapons
    ws:iterate(function(w, q)
        ws:decreaseWeapon(w, q)
    end)
    --  currently just give some bazookas
    for w, q in pairs(table_merge(scenario.weapons, scenario.tools)) do
        ws:addWeapon(lookupResource(w), q)
    end
    -- start target practice
    if scenario.timelimit then
        timer_limit = addTimer(scenario.timelimit, lost)
        local hud_status = TimeStatus_ctor()
        hud_status:set_showGameTime(true)
        raiseGlobalEvent("game_hud_add", hud_status)
        -- meh - must update display manually
        addWorkTimer(time("1s"), function()
            local left = timer_limit and timer_limit:timeLeft()
            if left then
                hud_status:set_gameRemaining(left)
            end
            return left ~= nil
        end)
    end
    targets_left = scenario.count
    trainee:team():set_active(true)
    cosleep(2)
    timer_check = addPeriodicTimer(time("0.5s"), check)
    timer_target = Timer.New()
    timer_target:setCallback(targetTimeout)
    timer_target:setDuration(scenario.target_timeout or time("30s"))
    -- oh man, how long until I found out that game messages are normally
    --  namespaced into game_msg, and that there's even already a hack to make
    --  them global... and that hack is to prepend the id with a '.'
    gameMessage(trainee, ".training.msg.start")
    targetSpawn()
end

function targetSpawn()
    assert(not target)
    target = target_class:createSprite()
    local drop, dest = Game:placeObjectRandom(target:physics():posp():radius())
    if not drop then
        target = nil
        log.error("oops, couldn't place target")
        return
    end
    -- xxx fishy, needed to enable the arrows (no team, no TeamTheme, no arrow)
    target:set_createdBy(trainee)
    --
    target:activate(drop)
    -- enable this as visual hint
    local seq = target:graphic()
    seq:set_cameraArrows(true)
    seq:set_positionArrow(true) -- don't use velocity, but direction
    timer_target:restart()
end

function targetHit(sender, obj, normal)
    assert(sender == target)
    obj = obj:backlink()
    local member = Control:memberFromGameObject(obj)
    if member ~= trainee then
        return
    end
    -- not if the worm itself touches the target (would be silly)
    if obj == trainee:sprite() then
        return
    end
    -- consider the target hit
    target:kill()
end

function targetTimeout()
    if not target then
        return
    end
    -- probably the target was somehow unreachable
    gameMessage(trainee, ".training.msg.retry")
    targets_left = targets_left + 1 -- blergh
    target:kill()
end

function targetKill(sender)
    assert(sender == target)
    target = nil
    timer_target:cancel()
    if winstate ~= nil then
        return
    end
    targets_left = targets_left - 1
    if targets_left <= 0 then
        won()
        return
    end
    gameMessage(trainee, ".training.msg.next", {tostring(targets_left)})
    targetSpawn()
end

-- periodic check for various conditions that would be hard to check on events
function check()
    -- projectile might be flying through the air and all that
    if Game:checkForActivity() then
        return
    end
    if not trainee:alive() then
        lost()
        return
    end
    -- check if the weaponset is empty
    local ws = trainee:team():weapons()
    local weapons_ok = false
    ws:iterate(function(weapon, count)
        if not weapons_ok then
            if scenario.weapons[weapon:name()] then
                weapons_ok = true
            end
        end
    end)
    if not weapons_ok then
        -- used up all your weapons; bye
        lost()
        return
    end
    -- maybe target spawning failed before; retry
    if not target then
        targetSpawn()
    end
end

function won()
    ending(true)
end

function lost()
    ending(false)
end

function ending(win)
    if winstate ~= nil then
        return
    end
    assert(type(win) == "boolean")
    winstate = win
    if winstate then
        gameMessage(trainee, ".training.msg.won")
        --trainee:team():youWinNow()
    else
        gameMessage(trainee, ".training.msg.lost")
    end
    killAll()
    if onend then
        addTimer(time("2s"), function() onend(winstate) end)
    end
end

function killAll()
    scenario = nil
    if timer_check then
        timer_check:cancel()
        timer_check = nil
    end
    if timer_limit then
        timer_limit:cancel()
        timer_limit = nil
    end
    if target then
        target:kill()
    end
    if hud_status then
        raiseGlobalEvent("game_hud_remove", hud_status)
        hud_status = nil
    end
end

init()
