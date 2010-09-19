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
        -- list of weapons that can be used to hit the target
        weapons = {
            w_bazooka = 10,
        },
        -- list of helpers for worm movement
        tools = std_tools,
        -- time the player has (nil if unlimited)
        timelimit = time("1min,30s"),
        -- number of targets that must be hit
        count = 5,
    },
    {
        weapons = {
            w_bow = 10,
        },
        tools = std_tools,
        timelimit = time("1min"),
        count = 5,
    }
}

local current

local function endgame(won)
    if won then
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
    start_training(current, endgame)
end

addGlobalEventHandler("game_start", function()
    endgame(nil)
end)
