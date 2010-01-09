-- Test file for lua gamemode
-- Currently just activates the first team

addGlobalEventHandler("game_start", function(sender)
    -- AV without errormsg when writing [0]
    Control_activateTeam(Control_teams()[1])
end)

-- simulate() equivalent
frameCallbackAdd(function()
    -- ...
end)
