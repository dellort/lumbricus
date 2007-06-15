module game.clientengine;

import game.gobject;
import game.physic;
import utils.mylist;
import utils.time;

class ClientGameEngine : GameObjectHandler {
    PhysicWorld mPhysicWorld;
    package List!(GameObject) mObjects;
    Time lastTime;
    Time currentTime;

    this() {
        mPhysicWorld = new PhysicWorld();

        mObjects = new List!(GameObject)(GameObject.node.getListNodeOffset());
    }

    void activate(GameObject obj) {
        mObjects.insert_tail(obj);
    }

    void deactivate(GameObject obj) {
        mObjects.remove(obj);
    }

    PhysicWorld physicworld() {
        return mPhysicWorld;
    }

    void doFrame(Time gametime) {
        currentTime = gametime;
        float deltaT = (currentTime - lastTime).msecs/1000.0f;
        mPhysicWorld.simulate(currentTime);
        //update game objects
        //NOTE: objects might be inserted/removed while iterating
        //      maybe one should implement a safe iterator...
        GameObject cur = mObjects.head;
        while (cur) {
            auto o = cur;
            cur = mObjects.next(cur);
            o.simulate(deltaT);
        }
        lastTime = currentTime;
    }

    //remove all objects etc. from the scene
    void kill() {
        //must iterate savely
        GameObject cur = mObjects.head;
        while (cur) {
            auto o = cur;
            cur = mObjects.next(cur);
            o.kill();
        }
    }
}
