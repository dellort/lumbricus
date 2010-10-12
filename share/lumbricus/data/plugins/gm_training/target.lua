-- target practice

local trainee -- a TeamMember
local target_class
local targets = {} -- set (sprite key, dummy value) of sprites for current targets
local timer_target -- timeout for hitting the target
local timer_check
local winstate -- nil: ongoing, false: lost, true: won
local targets_left -- number of targets that must be still hit
local targets_spawn -- number of targets to spawn
local timer_limit
local hud_status
local scenario -- current program
local onend

-- sc = scenario, see program.lua
-- endcallback = function called when user has won or lost
function start_training_target(a_trainee, a_scenario, endcallback)
    killAll()
    trainee = assert(a_trainee)
    scenario = table_copy(assert(a_scenario))
    scenario.multitarget = scenario.multitarget or 1
    assert(scenario.multitarget <= scenario.count)
    scenario.start_msg = scenario.start_msg or "start_target"
    onend = endcallback
    winstate = nil
    cospawn(initthread)
    return {
        kill = killAll,
    }
end

local function init()
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
    -- set weapons... training should go from simple to stronger weapons
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
        hud_status = HudGameTimer_ctor(Game)
        hud_status:set_showGameTime(true)
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
    targets_spawn = scenario.multitarget
    trainee:team():set_active(true)
    -- oh man, how long until I found out that game messages are normally
    --  namespaced into game_msg, and that there's even already a hack to make
    --  them global... and that hack is to prepend the id with a '.'
    gameMessage(trainee, ".training.msg." .. scenario.start_msg, nil, time("4s"))
    cosleep(2)
    if not scenario then
        return
    end
    -- select a (rather random) weapon - also fixes the bug/feature that a
    --  still selected weapon from last training round can still be fired, even
    --  if it was removed from the weaponset
    local weapon = next(scenario.weapons)
    weapon = weapon and lookupResource(weapon)
    trainee:control():selectWeapon(weapon)
    timer_check = addPeriodicTimer(time("0.5s"), check)
    timer_target = Timer.New()
    timer_target:setCallback(targetTimeout)
    timer_target:setDuration(scenario.target_timeout or time("30s"))
    checkSpawn()
end

-- see if targets need to be spawned (also finish "impartial" spawning when the
--  game engine couldn't place sprites)
function checkSpawn()
    checkWin()
    if winstate ~= nil or targets_spawn == nil then
        return
    end
    if targets_spawn == 0 and targets_left > 0 and table_empty(targets) then
        -- no targets in game / to spawn anymore, but still stuff left
        targets_spawn = min(targets_left, scenario.multitarget)
    end
    if targets_spawn > 0 then
        for i = 1, targets_spawn do
            -- if spawning fails, leave to next checkSpawn() call
            targetSpawn()
        end
    end
end

-- see if the worm has won by hitting all targets
function checkWin()
    if winstate ~= nil then
        return
    end
    if targets_left <= 0 then
        won()
        return
    end
end

function targetSpawn()
    local target = target_class:createSprite()
    local drop, dest = Game:placeObjectRandom(target:physics():posp():radius())
    if not drop then
        log.error("oops, couldn't place target")
        return nil
    end
    -- xxx fishy, needed to enable the arrows (no team, no TeamTheme, no arrow)
    target:set_createdBy(trainee)
    --
    targets[target] = true
    targets_spawn = targets_spawn - 1
    target:activate(drop)
    -- enable this as visual hint
    local seq = target:graphic()
    seq:set_cameraArrows(true)
    seq:set_positionArrow(true) -- don't use velocity, but direction
    -- *shrug*
    if scenario.multitarget == 1 then
        timer_target:restart()
    end
    return target
end

function targetHit(sender, obj, normal)
    assert(targets[sender])
    obj = obj:backlink()
    local member = Control:memberFromGameObject(obj)
    if member ~= trainee then
        return
    end
    -- not if the worm itself touches the target (would be silly)
    if obj == trainee:sprite() and not scenario.hit_on_touch then
        return
    end
    -- consider the target hit
    targets_left = targets_left - 1
    if targets_left > 0 then
        gameMessage(trainee, ".training.msg.next", {tostring(targets_left)})
    end
    sender:kill()
end

function targetTimeout()
    local target, _ = next(targets)
    if not target then
        return
    end
    -- probably the target was somehow unreachable
    gameMessage(trainee, ".training.msg.retry")
    target:kill()
end

function targetKill(sender)
    assert(targets[sender])
    targets[sender] = nil
    timer_target:cancel()
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
    -- maybe target spawning failed before; retry
    checkSpawn()
    if winstate ~= nil then
        return
    end
    -- check if the weaponset is empty
    --- (only if there were any weapons to begin with)
    if not table_empty(scenario.weapons) then
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
    end
    -- update health
    -- xxx there should be something that raises events when activity in the
    --  game starts or stops, so that we can update health on inactivity
    Control:updateHealth()
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
        gameMessage(trainee, ".training.msg.wonround")
        --trainee:team():youWinNow()
    else
        gameMessage(trainee, ".training.msg.lost")
    end
    trainee:team():set_active(false)
    if onend then
        killAll()
        addTimer(time("2s"), function()
            onend(winstate)
        end)
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
    while not table_empty(targets) do
        local target, dummy = next(targets)
        target:kill()
    end
    if hud_status then
        hud_status:set_visible(false)
        hud_status = nil
    end
end

init()
