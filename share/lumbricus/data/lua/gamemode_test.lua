-- Test file for lua gamemode
-- Currently just activates the first team

addGlobalEventHandler("game_start", function(sender)
    -- AV without errormsg when writing [0]
    -- ^ that's because [0] => nil => null => null pointer access in D code
    -- (passing null is only forbidden if it's a method call this pointer)
    Control_activateTeam(Control_teams()[1])

    -- for testing
    local status = TimeStatus_ctor()
    TimeStatus_set_showTurnTime(status, true)
    TimeStatus_set_showGameTime(status, true)
    raiseEvent(Game_globalEvents(), "game_hud_add", "timer", status)
end)

-- simulate() equivalent
frameCallbackAdd(function()
    -- ...
end)
