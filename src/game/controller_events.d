module game.controller_events;

//The idea behind this file is to have the whole "plugin interface" in a single
//  place, so when developing a plugin, you know where to look for available
//  events, instead of having to browse the whole code for declare() calls

import game.gamepublic;
import game.controller;
import game.game;
import game.gobject;
import game.sprite;
import game.crate;
import game.gamemodes.base;
import game.weapon.weapon;
import game.temp;
import utils.md;
import utils.reflection;
import utils.factory;

enum WormEvent {
    wormStartDie,   //starting to blow itself up
    wormDie,        //done blowing up
    wormDrown,      //death by drowning (reached ocean floor)
    wormActivate,
    wormDeactivate,
}

enum TeamEvent {
    skipTurn,
    surrender,
}

//this is the Controller "plugin interface", accessible by Controller.events
struct ControllerEvents {
    //active Gamemode
    MDelegate!(Gamemode) onGameStart;
    MDelegate!() onGameEnded;

    //cause, victim, damage, used weapon
    MDelegate!(GameObject, GObjectSprite, float, WeaponClass) onDamage;
    //number of pixels, cause
    MDelegate!(int, GameObject) onDemolition;

    //used weapon, refired
    MDelegate!(WeaponClass, bool) onFireWeapon; //xxx: broken, see wcontrol.d
    MDelegate!(WormEvent, TeamMember) onWormEvent;
    MDelegate!(TeamEvent, Team) onTeamEvent;

    MDelegate!(CrateType) onCrateDrop;
    MDelegate!(TeamMember, Collectable[]) onCrateCollect;

    //imo, sudden death is common enough to be here
    MDelegate!() onSuddenDeath;
    //also called on a tie, with winner = null
    MDelegate!(Team) onVictory;
}


//base class for custom plugins
//now I don't really know what the point of this class was anymore
abstract class GamePlugin : GameObject {
    protected {
        GameController controller;
    }

    this(GameEngine c) {
        super(c);
        controller = engine.controller;
    }
    this(ReflectCtor c) {
        super(c);
    }

    override bool activity() {
        return false;
    }
}

//the "AutoReg" bit is about that horrible regMethods() stuff
abstract class GamePluginAutoReg : GamePlugin {
    this(GameEngine c) {
        super(c);
        regMethods();
    }
    this(ReflectCtor c) {
        super(c);
        regMethods(c.types);
    }

    abstract protected void regMethods(Types t = null);

    static char[] genRegFunc(char[][] mnames) {
        char[] ret = `override protected void regMethods(Types t = null) {`;
        foreach (n; mnames) {
            ret ~= `
                if (t) {
                    t.registerMethod(this, &`~n~`, "`~n~`");
                }
                if (controller) {
                    controller.events.`~n~` ~= &`~n~`;
                }
                `;
        }
        ret ~= `}`;
        return ret;
    }

    //to override; I don't really know what this is...
    //Gamemodes can check it with Controller.isIdle()
    bool isIdle() {
        return true;
    }
}

//and another factory...
//plugins register here, so the Controller can load them
alias StaticFactory!("GamePlugins", GamePlugin, GameEngine)
    GamePluginFactory;
