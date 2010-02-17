module game.weapon.spawn;

import game.game;
import game.gfxset;
import game.gobject;
import game.sprite;
import game.weapon.weapon;
import utils.configfile;
import utils.vector2;
import utils.random;
import utils.randval;
import utils.misc;

import math = tango.math.Math;

//core spawn functions; actually, all spawn functions should use this
//lua has a spawnSprite function for this
void doSpawnSprite(SpriteClass sclass, GameObject spawned_by, Vector2f pos,
    Vector2f init_vel = Vector2f(0))
{
    argcheck(sclass);
    argcheck(spawned_by);

    Sprite sprite = sclass.createSprite(spawned_by.engine);
    sprite.createdBy = spawned_by;
    sprite.physics.setInitialVelocity(init_vel);
    sprite.activate(pos);
}

//classic airstrike in-a-row positioning, facing down
void spawnAirstrike(SpriteClass sclass, int count, GameObject shootbyObject,
    FireInfo about, int spawnDist)
{
    argcheck(sclass);
    argcheck(shootbyObject);
    auto engine = shootbyObject.engine;

    //direct into gravity direction
    if (about.dir.isNaN() || about.strength < float.epsilon)
        about.dir = Vector2f(0, 1);
    Vector2f destPos = about.pos;
    if (about.pointto.valid)
        destPos = about.pointto.currentPos;
    //y travel distance (spawn -> clicked point)
    float dy = destPos.y - engine.level.airstrikeY;
    if (dy > float.epsilon && math.abs(about.dir.x) > float.epsilon
        && about.strength > float.epsilon)
    {
        //correct spawn position, so airstrikes thrown at an angle
        //will still hit the clicked position
        float a = engine.physicworld.gravity.y;
        float v = about.dir.y*about.strength;
        //elementary physics ;)
        float t = (-v + math.sqrt(v*v+2.0f*a*dy))/a;  //time for drop
        float dx = t*about.dir.x*about.strength; //x movement while drop
        destPos.x -= dx;          //correct for x movement
    }
    //center around pointed
    float width = spawnDist * (count-1);

    for (int n = 0; n < count; n++) {
        Vector2f pos;
        pos.x = destPos.x - width/2 + spawnDist * n;
        pos.y = engine.level.airstrikeY;
        auto vel = about.dir*about.strength;
        doSpawnSprite(sclass, shootbyObject, pos, vel);
    }
}

//custom_dir is optional (considered not passed if x==y==0)
void spawnCluster(SpriteClass sclass, Sprite parent, int count,
    float strength_min, float strength_max, float random_range,
    Vector2f custom_dir = Vector2f(0))
{
    auto engine = parent.engine;
    auto spos = parent.physics.pos;
    if (custom_dir.x == 0 && custom_dir.y == 0) {
        custom_dir = Vector2f(0, -1);
    }
    for (int i = 0; i < count; i++) {
        auto strength = engine.rnd.rangef(strength_min, strength_max);
        auto theta = engine.rnd.rangef(-0.5, 0.5) * random_range
            * math.PI/180;
        auto dir = custom_dir.rotated(theta);
        //15???
        //-- dir * 15: add some distance from parent to clusters
        //--           (see above, I'm too lazy to do this properly now)
        doSpawnSprite(sclass, parent, spos + dir.normal * 15, dir * strength);
    }
}

