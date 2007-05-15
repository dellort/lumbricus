module game.physic;
import game.common;
import utils.mylist;
import utils.time;
import utils.vector2;
import log = utils.log;
import str = std.string;
import utils.output;

//simple physical object (has velocity, position, ...)
class PhysicObject {
    mixin ListNodeMixin node;

    PhysicWorld world;
    Vector2f pos;
    Vector2f velocity;

    void delegate() onUpdate;

    private void doUpdate() {
        if (onUpdate) {
            onUpdate();
        }
        world.mLog("update: %s", this);
    }

    char[] toString() {
        return str.format("%s: %s %s", toHash(), pos, velocity);
    }
}

class PhysicWorld {
    private List!(PhysicObject) mObjects;
    private uint mLastTime;

    private log.Log mLog;

    public void add(PhysicObject obj) {
        mObjects.insert_tail(obj);
        obj.world = this;
    }

    public void simulate(Time currentTime) {
        uint ms = currentTime.msecs();
        uint deltaTs = ms - mLastTime;
        mLastTime = ms;
        float deltaT = cast(float)deltaTs / 1000.0f;

        //wind/gravitation
        Vector2f force = Vector2f(0, 1.0f) * deltaT;

        foreach (PhysicObject o; mObjects) {
            //o.velocity *= deltaT;
            o.velocity += force;
            o.pos += o.velocity;
            o.doUpdate();
        }
    }

    this() {
        mObjects = new List!(PhysicObject)(PhysicObject.node.getListNodeOffset());
        mLog = log.registerLog("physlog");
    }
}
