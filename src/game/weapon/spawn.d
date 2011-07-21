module game.weapon.spawn;

import game.core;
import game.sprite;
import game.weapon.weapon;
import utils.vector2;
import utils.random;
import utils.randval;
import utils.misc;
import std.math;

/+
stuff that needs to be done:
- fix createdBy crap
- fix double damage (d0c needs to make up his mind)
  (actually implemented now, in explosionAt)
- for spawning from sprite, having something to specify the emit-position would
  probably be useful (instead of just using weapon-angle and radius); every
  decent shooter with more complex sprites has this
  (actually, FireInfo.pos fulfills this role right now)
- there's spawnFromFireInfo, but this concept sucks hard and should be replaced
+/

//core spawn functions; actually, all spawn functions should use this
Sprite spawnSprite(GameObject spawned_by, SpriteClass sclass, Vector2f pos,
    Vector2f init_vel = Vector2f(0))
{
    argcheck(sclass);
    //can now be null, although there are few legitimate usages for this
    //argcheck(spawned_by);

    Sprite sprite = sclass.createSprite();
    sprite.createdBy = spawned_by;
    sprite.activate(pos, init_vel);
    return sprite;
}

Sprite spawnFromFireInfo(SpriteClass sclass, Shooter shooter, FireInfo fireinfo)
{
    argcheck(sclass);
    argcheck(shooter);
    assert(!!shooter.owner);

    //creator and new sprite shouldn't touch
    auto dist = sclass.initPhysic.radius
        + shooter.owner.physics.posp.radius + 2;
    return spawnSprite(shooter, sclass, fireinfo.pos + fireinfo.dir * dist,
        fireinfo.dir * fireinfo.strength);
}

/+
void spawnFromShooter(SpriteClass sclass, Shooter shooter) {
    spawnFromFireInfo(sclass, shooter.fireinfo);
}
+/

//classic airstrike in-a-row positioning, facing down
void spawnAirstrike(SpriteClass sclass, int count, GameObject shootbyObject,
    FireInfo about, int spawnDist)
{
    argcheck(sclass);
    argcheck(shootbyObject);
    auto engine = sclass.engine;

    //direct into gravity direction
    if (about.dir.isNaN() || about.strength < float.epsilon)
        about.dir = Vector2f(0, 1);
    Vector2f destPos = about.pos;
    if (about.pointto.valid)
        destPos = about.pointto.currentPos;
    //y travel distance (spawn -> clicked point)
    float dy = destPos.y - engine.level.airstrikeY;
    if (dy > float.epsilon && abs(about.dir.x) > float.epsilon
        && about.strength > float.epsilon)
    {
        //correct spawn position, so airstrikes thrown at an angle
        //will still hit the clicked position
        float a = engine.physicWorld.gravity.y;
        float v = about.dir.y*about.strength;
        //elementary physics ;)
        float t = (-v + sqrt(v*v+2.0f*a*dy))/a;  //time for drop
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
        spawnSprite(shootbyObject, sclass, pos, vel);
    }
}

//custom_dir is optional (considered not passed if x==y==0)
void spawnCluster(SpriteClass sclass, Sprite parent, int count,
    float strength_min, float strength_max, float random_range,
    Vector2f custom_dir = Vector2f(0))
{
    argcheck(sclass);
    argcheck(parent);
    assert(!!parent.physics);

    auto engine = sclass.engine;
    auto spos = parent.physics.pos;
    if (custom_dir.x == 0 && custom_dir.y == 0) {
        custom_dir = Vector2f(0, -1);
    }
    for (int i = 0; i < count; i++) {
        auto strength = engine.rnd.rangef(strength_min, strength_max);
        auto theta = engine.rnd.rangef(-0.5, 0.5) * random_range
            * PI/180;
        auto dir = custom_dir.rotated(theta);
        //15???
        //-- dir * 15: add some distance from parent to clusters
        //--           (see above, I'm too lazy to do this properly now)
        spawnSprite(parent, sclass, spos + dir.normal * 15, dir * strength);
    }
}

