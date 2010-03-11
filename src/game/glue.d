module game.glue;

import utils.timesource;
import common.scene;
import game.controller; //: Team, TeamMember
import game.events;
import game.particles;
import game.weapon.weapon;
import utils.vector2;
import utils.time;
import utils.misc;

public import game.temp;

///calls from engine into clients
///for stuff that can't simply be polled
///anyone in the client engine can register callbacks here
class GameEngineCallback {

    //client/hud/GUI code can register game event handlers here
    Events cevents;

    //looks like I'm turning this into a dumping ground for other stuff

    //for transient effects
    ParticleWorld particleEngine;
    Scene scene;

    //needed for rendering team specific stuff (crate spies)
    TeamMember delegate() getControlledTeamMember;

    //used for interpolated/extrapolated drawing (see GameShell.frame())
    //NOTE: changes in arbitrary way on replays (restoring snapshots)
    TimeSourcePublic interpolateTime;

    //helper for profiling
    //returns the real time or thread time (depends from utils/perf.d) spent
    //  while drawing the game and non-GUI parts of the game hud (worm labels)
    Time delegate() getRenderTime;
}

