-- for each gravestone style, create a new sprite ("that was simplest")
-- because that's theme specific, try to see how many gravestone sequences
--  there are
-- the gravestone sequences are assumed to be s_grave0 ... s_graveN
local function create(id)
    local seq = Gfx_resource("s_grave" .. id, true)
    if not seq then
        return false
    end
    createSpriteClass {
        name = "gravestone" .. id,
        initPhysic = relay {
            collisionID = "grave",
            radius = 5,
            fixate = Vector2(0, 1),
            elasticity = 0.3,
            glueForce = 50,
            speedLimit = 1500,
        },
        sequenceType = seq,
    }
    return true
end
local i = 0
while create(i) do i = i + 1 end
