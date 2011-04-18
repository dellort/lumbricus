module game.plugin.messages;

import framework.lua;
import framework.i18n;
import game.controller;
import game.core;
import game.sprite;
import game.plugins;
import game.plugin.crate;
import game.weapon.weapon;
import game.weapon.weaponset;
import game.hud.messageviewer;
import utils.log;
import utils.configfile;
import utils.misc;
import utils.time;

import tango.util.Convert : to;

//the idea was that the whole game state should be observable (including
//events), so you can move displaying all messages into a separate piece of
//code, instead of creating messages directly
class MessagePlugin : GameObject {
    private {
        GameController mController;
        const cWinMessageTime = timeSecs(5.0f);
        Time mMessagesDone;
        int mMessageCounter;
        GameMessage[] mPendingMessages;
        TeamMember mLastMember;
        Team mWinner;
        HudMessageViewer mMessageViewer;
    }

    this(GameCore c, ConfigNode conf) {
        super(c, "msg_plugin");

        c.scripting.register(gMsgRegistry);
        c.addSingleton(this);
        c.scripting.addSingleton(this);

        mController = engine.singleton!(GameController)();
        mMessageViewer = new HudMessageViewer(c);
        if (!conf.getValue("no_default_msgs", false)) {
            auto ev = engine.events;
            OnGameStart.handler(ev, &onGameStart);
            OnGameEnd.handler(ev, &onGameEnd);
            OnSuddenDeath.handler(ev, &onSuddenDeath);
            OnSpriteDie.handler(ev, &onSpriteDie);
            OnTeamMemberStartDie.handler(ev, &onTeamMemberStartDie);
            OnTeamMemberSetActive.handler(ev, &onTeamMemberSetActive);
            OnTeamSkipTurn.handler(ev, &onTeamSkipTurn);
            OnTeamSurrender.handler(ev, &onTeamSurrender);
            OnCrateDrop.handler(ev, &onCrateDrop);
            OnTeamMemberCollectCrate.handler(ev, &onCrateCollect);
            OnVictory.handler(ev, &onVictory);
        }
    }

    private void onGameStart() {
        messageAdd("msggamestart", null);
    }

    private void onTeamMemberSetActive(TeamMember m, bool active) {
        if (active) {
            messageAdd("msgwormstartmove", [m.name], m.team, true);
        } else {
            mLastMember = m;
        }
    }

    private void onSpriteDie(Sprite sprite) {
        if (!sprite.isUnderWater())
            return;
        TeamMember m = mController.memberFromGameObject(sprite, false);
        if (!m)
            return;
        messageAdd("msgdrown", [m.name], m.team);
    }

    private void onTeamMemberStartDie(TeamMember m) {
        messageAdd("msgdie", [m.name], m.team);
    }

    private void onTeamSkipTurn(Team t) {
        messageAdd("msgskipturn", [t.name()], t);
    }

    private void onTeamSurrender(Team t) {
        messageAdd("msgsurrender", [t.name()], t);
    }

    private void onCrateDrop(CrateSprite sprite) {
        switch (sprite.crateType()) {
            case CrateType.med:
                messageAdd("msgcrate_medkit");
                break;
            case CrateType.tool:
                messageAdd("msgcrate_tool");
                break;
            default:
                messageAdd("msgcrate");
        }
    }

    private void onCrateCollect(TeamMember member, CrateSprite crate) {
        foreach (item; crate.stuffies) {
            //someone lieks code duplication...
            if (auto weapon = cast(CollectableWeapon)item) {
                //weapon
                messageAdd("collect_item", [member.name(),
                    "_." ~ item.id(), to!(string)(weapon.quantity)],
                    member.team, true);
            } else if (auto medkit = cast(CollectableMedkit)item) {
                //medkit
                messageAdd("collect_medkit", [member.name(),
                    to!(string)(medkit.amount)], member.team, true);
            } else if (auto tool = cast(CollectableTool)item) {
                //tool
                messageAdd("collect_tool", [member.name(),
                    "_." ~ item.id()], member.team, true);
            } else if (auto bomb = cast(CollectableBomb)item) {
                //crate with bomb
                messageAdd("collect_bomb", [member.name()],
                    member.team, true);
            }
        }
    }

    private void onSuddenDeath() {
        messageAdd("msgsuddendeath");
    }

    private void onVictory(Team member) {
        mWinner = member;
        if (mLastMember && mLastMember.team !is mWinner) {
            //xxx this should only be executed for "turnbased" game mode,
            //  but there must be a better way than checking the mode
            //  explicitly
            messageAdd("msgwinstolen",
                [mWinner.name, mLastMember.team.name], mWinner, false,
                    cWinMessageTime);
        } else {
            messageAdd("msgwin", [mWinner.name], mWinner, false,
                cWinMessageTime);
        }
    }

    private void onGameEnd() {
        if (!mWinner) {
            messageAdd("msgnowin", null, null, false, cWinMessageTime);
        }
        //xxx is this really useful? I would prefer showing the
        //  "team xxx won" message longer
        //messageAdd("msggameend");
    }

    private void messageAdd(string msg, string[] args = null, Team actor = null,
        bool is_private = false, Time displayTime = GameMessage.cMessageTime)
    {
        GameMessage gameMsg;
        gameMsg.lm.id = msg;
        gameMsg.lm.args = args;
        gameMsg.color = actor ? actor.theme : null;
        gameMsg.is_private = is_private;
        gameMsg.displayTime = displayTime;
        add(gameMsg);
    }

    void add(GameMessage msg) {
        //no point in setting that manually
        msg.lm.rnd = engine.rnd.next;

        //maybe reset wait time
        if (mMessagesDone < engine.gameTime.current)
            mMessagesDone = engine.gameTime.current;
        mMessagesDone += msg.displayTime;

        if (mMessageViewer.onMessage)
            mMessageViewer.onMessage(msg);
    }

    override bool activity() {
        //xxx actually, this is a bit wrong, because even messages the client
        //    won't see (viewer field set) count for wait time
        //    But to stay deterministic, we can't consider that
        //in other words, all clients wait for the same time
        if (mMessagesDone < engine.gameTime.current) {
            //did wait long enough
            return false;
        }
        return true;
    }

    static this() {
        GamePluginFactory.register!(typeof(this))("messages");
    }
}

private LuaRegistry gMsgRegistry;

static this() {
    gMsgRegistry = new typeof(gMsgRegistry)();

    gMsgRegistry.methods!(MessagePlugin, "add");
}
