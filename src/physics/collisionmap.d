module physics.collisionmap;

import physics.base;
import physics.contact;
import physics.misc;

import utils.array : arrayMap;
import utils.configfile;
import utils.reflection;
import utils.misc;

import str = stdx.string;
import tango.util.Convert;

//for loading from ConfigNode
private const char[][ContactHandling.max+1] cChNames =
    ["", "hit", "hit_noimpulse", "hit_pushback"];

//handling of the collision map
class CollisionMap {
    CollisionType[char[]] mCollisionNames;
    CollisionType[] mCollisions; //indexed by CollisionType.index
    //pairs of things which collide with each other
    CollisionType[2][][ContactHandling.max+1] mHits;

    //CollisionType.index indexes into this, see canCollide()
    ContactHandling[][] mTehMatrix;

    //if there are still unresolved CollisionType forward references
    //used for faster error checking (in canCollide() which is a hot-spot)
    bool mHadCTFwRef = true;

    //special types
    CollisionType mCTAlways, mCTNever, mCTAll;

    CollideDelegate mCollideHandler;

    this (ReflectCtor c) {
    }

    CollisionType newCollisionType(char[] name) {
        assert(!(name in mCollisionNames));
        auto t = new CollisionType();
        t.name = name;
        mCollisionNames[t.name] = t;
        t.index = mCollisions.length;
        mCollisions ~= t;
        mHadCTFwRef = true; //because this is one
        return t;
    }

    public CollisionType collideNever() {
        return mCTNever;
    }
    public CollisionType collideAlways() {
        return mCTAlways;
    }

    //associate a collision handler with code
    //this can handle forward-referencing
    public void setCollideHandler(CollideDelegate oncollide) {
        mCollideHandler = oncollide;
    }

    public ContactHandling canCollide(CollisionType a, CollisionType b) {
        if (mHadCTFwRef) {
            checkCollisionHandlers();
        }
        assert(a && b, "no null parameters allowed, use collideNever/Always");
        assert(!a.undefined && !b.undefined, "undefined collision type");
        return mTehMatrix[a.index][b.index];
    }

    public ContactHandling canCollide(PhysicBase a, PhysicBase b) {
        assert(a && b);
        if (!a.collision)
            assert(false, "no collision for "~a.toString());
        if (!b.collision)
            assert(false, "no collision for "~b.toString());
        return canCollide(a.collision, b.collision);
    }

    //call the collision handler for these two objects
    public void callCollide(Contact c) {
        assert(!!mCollideHandler);
        mCollideHandler(c);
    }

    //check if all collision handlers were set; if not throw an error
    public void checkCollisionHandlers() {
        char[][] errors;

        foreach(t; mCollisions) {
            if (t.undefined) {
                errors ~= t.name;
            }
        }

        if (errors.length > 0) {
            throw new Exception(myformat("the following collision names were"
                " referenced, but not defined: {}", errors));
        }

        mHadCTFwRef = false;
    }

    //find a collision ID by name
    public CollisionType findCollisionID(char[] name) {
        if (name.length == 0) {
            return mCTNever;
        }

        if (name in mCollisionNames)
            return mCollisionNames[name];

        //a forward reference
        //checkCollisionHandlers() verifies if these are resolved
        return newCollisionType(name);
    }

    public CollisionType[] collisionTypes() {
        return mCollisions.dup;
    }

    //will rebuild mTehMatrix
    void rebuildCollisionStuff() {
        //return an array containing all transitive subclasses of cur
        CollisionType[] getAll(CollisionType cur) {
            CollisionType[] res = [cur];
            foreach (s; cur.subclasses) {
                res ~= getAll(s);
            }
            return res;
        }

        //set if a and b should collide to what
        void setCollide(CollisionType a, CollisionType b,
            ContactHandling what = ContactHandling.normal)
        {
            mTehMatrix[a.index][b.index] = what;
            mTehMatrix[b.index][a.index] = what;
        }

        mCTAlways.undefined = false;
        mCTNever.undefined = false;
        mCTAll.undefined = false;
        mHadCTFwRef = false;

        //allocate/clear the matrix
        mTehMatrix.length = mCollisions.length;
        foreach (ref line; mTehMatrix) {
            line.length = mTehMatrix.length;
            line[] = ContactHandling.none;
        }

        foreach (ct; mCollisions) {
            mHadCTFwRef |= ct.undefined;
        }

        //relatively hack-like, put in all unparented collisions as subclasses,
        //without setting their parent member, else loadCollisions could cause
        //problems etc.; do that only for getAll()
        mCTAll.subclasses = null;
        foreach (ct; mCollisions) {
            if (!ct.superclass && ct !is mCTAll)
                mCTAll.subclasses ~= ct;
        }

        for (ContactHandling ch = ContactHandling.normal;
            ch <= ContactHandling.max; ch++)
        {
            foreach (CollisionType[2] entry; mHits[ch]) {
                auto a = getAll(entry[0]);
                auto b = getAll(entry[1]);
                foreach (xa; a) {
                    foreach (xb; b) {
                        setCollide(xa, xb, ch);
                    }
                }
            }
        }

        foreach (ct; mCollisions) {
            setCollide(mCTAlways, ct, ContactHandling.normal);
            setCollide(mCTNever, ct, ContactHandling.none);
        }
        //lol paradox
        setCollide(mCTAlways, mCTNever, ContactHandling.none);
    }

    //"collisions" node from i.e. worm.conf
    public void loadCollisions(ConfigNode node) {
        auto defines = str.split(node.getStringValue("define"));
        foreach (d; defines) {
            auto cid = findCollisionID(d);
            if (!cid.undefined) {
                throw new Exception("collision name '" ~ cid.name
                    ~ "' redefined");
            }
            cid.undefined = false;
        }
        foreach (char[] name, char[] value; node.getSubNode("classes")) {
            //each entry is class = superclass
            auto cls = findCollisionID(name);
            auto supercls = findCollisionID(value);
            if (cls.superclass) {
                throw new Exception("collision class '" ~ cls.name ~ "' already"
                    ~ " has a superclass");
            }
            cls.superclass = supercls;
            //this is what we really need
            supercls.subclasses ~= cls;
            //check for cirular stuff
            auto t = cls;
            CollisionType[] trace = [t];
            while (t) {
                t = t.superclass;
                trace ~= t;
                if (t is cls) {
                    throw new Exception("circular subclass relation: " ~
                        str.join(arrayMap(trace, (CollisionType x) {
                            return x.name;
                        }), " -> ") ~ ".");
                }
            }
        }

        void readCH(char[] nname, ContactHandling ch) {
            foreach (char[] name, char[] value; node.getSubNode(nname)) {
                //each value is an array of collision ids which
                // collide with "name"
                auto hits = arrayMap(str.split(value), (char[] id) {
                    return findCollisionID(id);
                });
                auto ct = findCollisionID(name);
                foreach (h; hits) {
                    mHits[ch] ~= [ct, h];
                }
            }
        }

        for (ContactHandling ch = ContactHandling.normal;
            ch <= ContactHandling.max; ch++)
        {
            readCH(cChNames[ch], ch);
        }
        rebuildCollisionStuff();
    }

    this() {
        mCTAlways = findCollisionID("always");
        mCTAll = findCollisionID("all");
        mCTNever = findCollisionID("never");
    }
}
