-- executed at start of program

-- crude test: spawn the game over and over, and look at memory use at the end
function testgc(count)
    --spawn("stats")
    count = count or 10
    cospawn(function()
        for y = 1, count do
            local game = spawn("game")
            cosleep(time("1s"))
            game:kill()
            -- get rid of pinned GameTask D object
            game = nil
            collectgarbage("collect")
            -- and all the garbage on the D heap the game left behind
            exec("gc false")
        end
    end)
end

--testgc()
