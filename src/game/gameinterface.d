module game.gameinterface;

import utils.configfile;
import utils.vector2;
import utils.time;

//Hint: there's a limited number of predefined colors; that's because sometimes
//colors are hardcoded in animations, etc.
//so, these are not just color names, but also linked to these animations
static const char[][] cTeamColors = [
    "red",
    "blue",
    "green",
    "yellow",
    "magenta",
    "cyan",
];

///data sent to controller when a team joins the game
struct TeamDescriptor {
    ///team name (does not need to be unique)
    char[] name;
    ///team members
    ///order is important, as members may be referenced by array index
    char[][] members;
    ///index into predefined team colors
    int teamColorId;

    ///node = the node describing a single team
    static TeamDescriptor opCall(ConfigNode node) {
        TeamDescriptor ret;
        ret.name = node.getStringValue("name", "teamUnnamed");
        ret.teamColorId = node.selectValueFrom("color", cTeamColors, 0);
        foreach (char[] name, char[] value; node.getSubNode("member_names")) {
            ret.members ~= value;
        }
        return ret;
    }
}

///current state of game
///some states make more sense in a network game
enum GameState {
    loading,            ///game is loading and not ready for any interaction
    waitingForPlayers,  ///game is waiting for teams to join and will start soon
    starting,           ///no more joining, game will begin (counting down oslt)
    running,            ///game is running, no joining
    ending,             ///game has ended and will soon shut down
}

///which style a worm should jump
enum JumpMode {
    normal,      ///standard forward jump (return)
    smallBack,   ///little backwards jump (double return)
    backFlip,    ///large backwards jump/flip (double backspace)
    straightUp,  ///jump straight up (backspace)
}

///this tells the client the state (i.e. possible interactions) of the currently
///active worm (no animation states etc)
///(client information only, to update the gui/map keys or something)
///note that targetting weapons are not affected by this, as target selection is
///a client thing
enum WalkState {
    walk,           ///worm is on the ground and could walk normally
    jetpackFly,     ///flying a jetpack
    swing,          ///hanging on a rope
    floating,       ///floating down on a parachute
    remoteControl,  ///remote-controlling something (e.g. super sheep)
    noMovement,     ///worm is being thrown around/firing a weapon/waiting for
                    ///a state transition and cannot be controlled
}

///tells if and what kinds of weapons can be used (draw, aim, fire)
enum WeaponMode {
    noWeapons,          ///no use of weapons possible
                        ///(falling, retreating after fire, ...)
    fullWeapons,        ///full weapon set available
    secondaryWeapons,   ///limited weapon set (jetpack-flying, ...)
}

///short out-of-game information about running game
struct GameInformation {
    char[] gameName;
    GameState state;
    int maxPlayers;
    char[][] connectedClients;
    //xxx add more
}

///out-of-game interface of game controller
///responsible for establishing a connection to the game
interface ControllerSetupIfc {
    ///connect to the game (does not mean to really participate)
    ControllerGameIfc connect(ClientGameIfc cl, char[] clientName);

    ///get some info about running game
    GameInformation getInformation();
}

///in-game interface of game controller
interface ControllerGameIfc {
    ///disconnect from the game
    ///remaining teams will die with your connection
    void disconnect();

    ///join the game with a pack of worms
    ///depending on game mode/settings, not all team members will really
    ///appear in-game, or you may get random additional members assigned
    TeamControllerIfc joinGame(ClientTeamIfc client, TeamDescriptor team);

    //xxx add everything needed to draw the game scene
    //this is a hack until we make something up to sync client/server view
}

///team controller interface used by client
///with this interface, only the associated team can be controlled
interface TeamControllerIfc {
    ///flee from the battlefield
    void disconnect();

    ///select the next worm in row
    ///this does not have to work, nothing will happen if selecting is not
    ///possible
    void selectNextMember();

    ///make the active worm jump
    void jump(JumpMode mode);

    ///set jetpack mode
    //xxx making this a function assumes that the jetpack is not a weapon
    void jetpack(bool active);

    ///set the movement vector for the active worm
    ///only the sign counts, speed is always fixed
    ///the worm will move by this vector from this call on
    ///(0,0) to stop
    ///note that the worm may stop by itself for several explosive reasons
    void setMovement(Vector2i m);

    ///select weapon weaponId for the active worm
    void weaponDraw(char[] weaponId);

    ///set grenade timer
    void weaponSetTimer(int timerSecs);

    ///set firing angle, possible angles depend on selected weapon
    ///will be rounded for weapons with fixed angles
    void weaponAim(float angle);

    ///set target of targetting weapon, showing a big X on the hated opponent
    ///how the target is accquired (e.g. mouse click, use same as last, ...)
    ///is handled by the client
    void weaponSetTarget(Vector2i targetPos);

    ///start firing a weapon (i.e. charge by hammering spacebar)
    ///angle, timer etc. are not locked after this
    ///will deactivate worm movement
    void weaponStartFire();

    ///actually fire weapon with parameters set before
    ///needs a preceeding call of weaponStartFire with current weapon to work
    ///strength is client-selected and not calculated from time between calls
    ///to avoid network lag errors
    void weaponFire(float strength);
}

///callback interface for one team, used by controller, implemented by client
///most functions provide status information on change to avoid constant polling
interface ClientTeamIfc {
    ///set if its this teams' turn
    ///multiple teams can be active at the same time, depending on game mode
    void setActive(bool active);

    ///Time remaining of teams' round time, shown ticking down if not paused
    ///not all game modes have to use this
    void roundTime(Time t, bool timePaused);

    ///another team member has become active
    ///(de)activating means gaining/losing control of the member
    ///one example is worm switching
    void activateMember(int memberId, bool active);

    ///set if it is currently possible to select another worm (update gui)
    void selectionPossible(bool allowSelect);

    ///what kind of movement control is possible
    void memberWalkState(WalkState state);

    ///what kinds of weapons can be used at the current member state
    ///e.g. no weapons while in mid-air
    void memberWeaponMode(WeaponMode mode);

    ///feedback for drawing weapons, as weapon selection may be changed by
    ///controller (out of ammo, jetpack activated, ...) (xxx should it be?)
    void weaponDraw(char[] weaponId);
}

///general game callback interface, not dependant on a particular team
///most values are used to update the gui
interface ClientGameIfc {
    ///called whenever game state changes
    ///times are for current state and can be 0,0 if not available
    void gameState(GameState st, Time fullTime, Time remainingTime);

    ///wind change over time, speed is target speed
    //xxx physics problems in network mode due to timing
    void windChange(float speed, Time changeTime);

    ///water level change over time, level is target
    void waterChange(float level, Time changeTime);

    ///update total game timer, client will show time ticking down if not paused
    void gameTime(Time t, bool timePaused);

    ///sudden-death mode starting
    void startSuddenDeath();

    ///is the game completely paused
    void gamePaused(bool paused);
}
