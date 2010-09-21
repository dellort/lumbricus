local std_tools = {
    w_jetpack = 25,
    w_superrope = 25,
    w_beamer = 5,
}

-- each item is a "scenario" where the user is challenged to some boring
--  training with a specific weapon - the secenarios are "executed" in sequence;
--  the user progresses to the next stage as he wins
training_program = {
    {
        type = start_training_target,
        -- list of weapons that can be used to hit the target
        weapons = {
            w_bazooka = 20,
        },
        -- list of helpers for worm movement
        tools = std_tools,
        -- time the player has (nil if unlimited)
        timelimit = time("1min,30s"),
        -- number of targets that must be hit
        count = 5,
        -- number of targets to spawn at once (default: 1)
        multitarget = 5,
    },
    {
        type = start_training_target,
        weapons = {
            w_bazooka = 10,
        },
        tools = std_tools,
        timelimit = time("1min,30s"),
        count = 5,
    },
    {
        type = start_training_target,
        weapons = {
            w_bow = 10,
        },
        tools = std_tools,
        timelimit = time("1min"),
        count = 5,
    },
    {
        type = start_training_target,
        -- start message; defaults to "start_target"
        start_msg = "start_movement",
        weapons = {},
        tools = std_tools,
        timelimit = time("1min"),
        multitarget = 10,
        count = 10,
        -- count as hit when worm touches target (defaults to false)
        -- xxx lame, but could be awesome for rope practice
        -- xxx-2 should use a sensor only, instead of a solid sprite?
        hit_on_touch = true,
    },
}

local current
local current_ctx

local function endgame(won)
    current_ctx = nil
    -- there should be exactly 1 team/member
    local trainee = assert(Control:teams()[1]:members()[1])
    -- died completely?
    if not trainee:alive() then
        Control:endGame()
        return
    end
    --
    if won == true then
        for i = 1, #training_program do
            if training_program[i] == current then
                current = training_program[i+1]
                break
            end
        end
    end
    if current == nil then
        current = training_program[1]
    end
    local fn = assert(current.type)
    current_ctx = fn(trainee, current, endgame)
end

-- skip the current training step and start the next (cheat/debugging/feature)
function _G.skipTraining()
    if current_ctx then
        current_ctx.kill()
        endgame(true)
    end
end

addGlobalEventHandler("game_start", function()
    endgame(nil)
end)
