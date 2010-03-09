local M = export_table()

-- depends from napalm
local s = createSpriteClass {
    name = "barrel",
    noActivityWhenGlued = true,
    initPhysic = relay {
        radius = 10,
        mass = 10,
        glueForce = 50,
        collisionID = "levelobject",
        damageable = 1.0,
        fixate = Vector2(0, 1),
        elasticity = 0.4,
    },
    sequenceType = "s_barrel",
    initialHp = 15,
}
addSpriteClassEvent(s, "sprite_zerohp", function(sender)
    spriteExplode(sender, 50)
    -- actually I have no idea what the strength params mean (4th/5th param)
    spawnCluster(M.standard_napalm, sender, 40, 0, 0, 60)
end)
