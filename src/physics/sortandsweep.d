/*
* Sort and sweep broadphase collision detector
* Adapted from Blaze (BSD license):
*   Copyright (c) 2008 Mason Green http://www.dsource.org/projects/blaze
*/
module physics.sortandsweep;

import physics.broadphase;
import physics.contact;
import physics.world;
import utils.array;
import utils.vector2;

class BPSortAndSweep : BroadPhase {
    private {
        int mSortAxis = 0;
        PhysicObject[] mObjArr;
    }

    this(PhysicWorld a_world) {
        super(a_world);
    }

    override void add(PhysicObject o) {
        super.add(o);
        mObjArr ~= o;
    }
    override void remove(PhysicObject o) {
        super.remove(o);
        arrayRemoveUnordered(mObjArr, o);
    }

    override void collide(CollideDelegate contactHandler) {
        auto shapes = mObjArr;

        shellSort(shapes, mSortAxis);

        /// Sweep the array for collisions
        Vector2f s, s2, v;
        for (int i = 0; i < shapes.length; i++)
        {
            PhysicObject cur = shapes[i];

            /// Determine AABB center point
            Vector2f p = cur.pos;

            /// Update sum and sum2 for computing variance of AABB centers
            s += p;
            s2 += p.mulEntries(p);

            /// Test collisions against all possible overlapping AABBs following current one
            for (int j = i + 1; j < shapes.length; j++) {
                /// Stop when tested AABBs are beyond the end of current AABB
                if (shapes[j].bb.p1[mSortAxis] > cur.bb.p2[mSortAxis])
                    break;

                if (shapes[j].bb.p1[!mSortAxis] > cur.bb.p2[!mSortAxis]
                    || shapes[j].bb.p2[!mSortAxis] < cur.bb.p1[!mSortAxis])
                    continue;

                checkObjectCollision(cur, shapes[j], contactHandler);
            }
        }

        /// Compute variance (less a, for comparison unnecessary, constant factor)
        v = s2 - s.mulEntries(s) / shapes.length;

        /// Update axis sorted to be the one with greatest AABB variance
        mSortAxis = 0;
        if (v.y > v.x) mSortAxis = 1;
    }

    ///
    private void shellSort(PhysicObject[] shapes, int sortAxis)
    {
        bool compareObj(PhysicObject obj1, PhysicObject obj2) {
            return obj1.bb.p1[sortAxis] > obj2.bb.p1[sortAxis];
        }

        int increment = cast(int)(shapes.length * 0.5f + 0.5f);

        while (increment > 0) {
            for (int i = increment; i < shapes.length; i++) {
                int j = i;
                PhysicObject temp = shapes[i];

                while ((j >= increment)
                    && (compareObj(shapes[j - increment], temp)))
                {
                    shapes[j] = shapes[j - increment];
                    j = j - increment;
                }
                shapes[j] = temp;
            }

            if (increment == 2)
                increment = 1;
            else
                increment = cast(int)(increment * 0.45454545f + 0.5f);
        }
    }

}
