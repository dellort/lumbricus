module physics.collisionmap;

import utils.array : arrayMap;
import utils.configfile;
import utils.misc;

import str = utils.string;
import tango.util.Convert;

//entry in matrix that defines how a collision should be handled
//for other uses than contact generation (like triggers), any value >0
//  means it collides
enum ContactHandling : ubyte {
    none,       //no collision
    normal,     //default (physically correct) handling
    noImpulse,  //no impulses are exchanged (like both objects hit a wall)
                //this may be useful if you want an object to block,
                // but not be moved
    pushBack,   //push object back where it came from (special case for ropes)
}

//for loading from ConfigNode
private const char[][ContactHandling.max+1] cChNames =
    ["", "hit", "hit_noimpulse", "hit_pushback"];

//the physics stuff uses an ID to test if collision between objects is wanted
//all physic objects (type PhysicBase) have an CollisionType
//ok, it's not really an integer ID anymore, but has the same purpose
final class CollisionType {
    private {
        //index into the collision-matrix
        int mIndex;

        char[] mName;

        //needed because of forward referencing etc.
        CollisionType mSuperClass;
        CollisionType[] mSubClasses;
    }

    this() {
    }

    char[] name() { return mName; }

    char[] toString() {
        return "[CollisionType "~name~"]";
    }
}

//it's illegal to use CollisionType_Invalid in PhysicBase.collision
const CollisionType CollisionType_Invalid = null;

//the collision map is a helper for the game logic, and decides which objects
//  can or can not collide
//(has nothing to do with the actual collision functions etc.)
final class CollisionMap {
    private {
        CollisionType[char[]] mCollisionNames;
        CollisionType[] mCollisions; //indexed by CollisionType.index
        //pairs of things which collide with each other
        CollisionType[2][][ContactHandling.max+1] mHits;

        //CollisionType.index indexes into this, see canCollide()
        ContactHandling[][] mTehMatrix;

        //special types
        CollisionType mCTRoot;   //superclass of all collision types
        CollisionType mCTAlways, mCTNone;

        //mTehMatrix is outdated
        bool mDirty;
        //no further changes allowed
        bool mSealed;
    }

    this() {
        mCTRoot = newCollisionType("root", null);
        mCTAlways = newCollisionType("always", mCTRoot);
        enableCollision(mCTAlways, mCTRoot);
        mCTNone = newCollisionType("none", mCTRoot);
    }

    CollisionType root() { return mCTRoot; }
    CollisionType always() { return mCTAlways; }
    CollisionType none() { return mCTNone; }

    CollisionType newCollisionType(char[] name, CollisionType ct_super) {
        if (mCTRoot)
            argcheck(!!ct_super);
        assert(!mSealed);
        argcheck(name.length > 0, "b");
        if (name in mCollisionNames)
            throw new CustomException("collision type already exists: "~name);
        auto t = new CollisionType();
        t.mName = name;
        t.mSuperClass = ct_super;

        //this is what we really need (see getAll() in rebuildCollisionStuff())
        if (ct_super)
            ct_super.mSubClasses ~= t;

        mCollisionNames[t.mName] = t;
        t.mIndex = mCollisions.length;
        mCollisions ~= t;

        mDirty = true;

        return t;
    }

    public ContactHandling canCollide(CollisionType a, CollisionType b) {
        assert(a && b, "no null parameters allowed, use collideNever/Always");
        if (mDirty)
            rebuildCollisionStuff();
        return mTehMatrix[a.mIndex][b.mIndex];
    }

    //find a collision ID by name
    public CollisionType find(char[] name) {
        if (auto pres = name in mCollisionNames)
            return *pres;

        throw new CustomException("collision ID '"~name~"' not found.");
    }

    alias find findCollisionID;

    public CollisionType[] collisionTypes() {
        return mCollisions.dup;
    }

    //will rebuild mTehMatrix
    void rebuildCollisionStuff() {
        //allocate/clear the matrix
        mTehMatrix.length = mCollisions.length;
        foreach (ref line; mTehMatrix) {
            line.length = mTehMatrix.length;
            line[] = ContactHandling.none;
        }

        //set if a and b should collide to what
        void setCollide(CollisionType a, CollisionType b, ContactHandling what)
        {
            mTehMatrix[a.mIndex][b.mIndex] = what;
            mTehMatrix[b.mIndex][a.mIndex] = what;
        }

        //return an array containing all transitive subclasses of cur
        CollisionType[] getAll(CollisionType cur) {
            CollisionType[] res = [cur];
            foreach (s; cur.mSubClasses) {
                res ~= getAll(s);
            }
            return res;
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

        mDirty = false;
    }

    void enableCollision(CollisionType a, CollisionType b,
        ContactHandling ch = ContactHandling.normal)
    {
        assert(!mSealed);
        //indirection through tmp is to work around a ldc bug
        CollisionType[2] tmp = [a, b];
        mHits[ch] ~= tmp;
        mDirty = true;
    }

    //"collisions" node from i.e. worm.conf
    public void loadCollisions(ConfigNode node) {
        foreach (char[] name, char[] value; node.getSubNode("classes")) {
            //each entry is class = superclass
            auto supercls = findCollisionID(value);
            newCollisionType(name, supercls);
        }

        for (ContactHandling ch = ContactHandling.normal;
            ch <= ContactHandling.max; ch++)
        {
            char[] nname = cChNames[ch];
            foreach (char[] name, char[] value; node.getSubNode(nname)) {
                //each value is an array of collision ids which
                // collide with "name"
                auto hits = arrayMap(str.split(value), (char[] id) {
                    return findCollisionID(id);
                });
                auto ct = findCollisionID(name);
                foreach (h; hits) {
                    enableCollision(ct, h, ch);
                }
            }
        }
    }

    //debugging: don't allow any further changes after this hs been called
    void seal() {
        mSealed = true;
        rebuildCollisionStuff();
    }
}
