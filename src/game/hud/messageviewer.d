module game.hud.messageviewer;

import framework.font;
import framework.i18n;
import common.scene;
import game.controller;
import game.core;
import game.teamtheme;
import game.hud.hudbase;
import game.hud.teaminfo;
import gui.widget;
import gui.label;
import utils.misc;
import utils.time;
import utils.queue;
import utils.interpolate;
import utils.vector2;

class HudMessageViewer : HudElementWidget {
    void delegate(GameMessage msg) onMessage;

    this(GameCore engine) {
        super(engine);
        auto w = new MessageViewer(engine, this);
        auto lay = WidgetLayout.Aligned(0, -1, Vector2i(0, 5));
        lay.border = Vector2i(5, 1);
        w.setLayout(lay);
        set(w);
    }
}

///let the client display a message (like it's done on round's end etc.)
///this is a bit complicated because message shall be translated on the
///client (i.e. one client might prefer Klingon, while the other is used
///to Latin); so msgid and args are passed to the translation functions
///this returns a value, that is incremented everytime a new message is
///available
///a random int is passed along, so all clients with the same locale
///will select the same message
struct GameMessage {
    const cMessageTime = timeSecs(1.5f);

    LocalizedMessage lm;
    //Actor actor;    //who did the action (normally a TeamMember), may be null
    TeamTheme color;//for message color, null for neutral
    bool is_private;//who should see it (only players with same color see it),
                    //  false for all
    Time displayTime = cMessageTime;
}

//Linear up -> wait -> down -> wait
float msgAnimate(float x, Time total) {
    const cAnimateMs = 0.15f;
    const cPauseMs = 0.25f;

    float totalSecs = total.secsf();
    float curSecs = totalSecs*x;
    if (curSecs < cAnimateMs)
        return curSecs/cAnimateMs;
    else if (curSecs < totalSecs - (cAnimateMs + cPauseMs))
        return 1.0f;
    else if (curSecs < totalSecs - cPauseMs)
        return (totalSecs - cPauseMs - curSecs)/cAnimateMs;
    else
        return 0;
}

class MessageViewer : Label {
    private {
        GameCore mEngine;
        Queue!(GameMessage) mMessages;

        Translator mLocaleMsg;

        InterpolateFnTime!(int, msgAnimate) mInterp;

        //blergh
        FontProperties mStdFont;
    }

    this(GameCore engine, HudMessageViewer link) {
        mEngine = engine;
        link.onMessage = &showMessage;
        mLocaleMsg = localeRoot.bindNamespace("game_msg");

        styles.addClass("preparebox");
        mStdFont = gFontManager.getStyle("messages");
        setFont(mStdFont);
        //make sure it's hidden initially
        mInterp.init(timeSecs(0), -200, 0);

        mMessages = new typeof(mMessages);
    }

    //return true as long messages are displayed
    bool working() {
        return !mMessages.empty || mInterp.inProgress;
    }

    bool idle() {
        return !working();
    }

    private void setFont(ref FontProperties props) {
        styles.setStyleOverrideT!(Font)("text-font",
            gFontManager.create(props));
    }

    private void showMessage(GameMessage msg) {
        if (msg.is_private && msg.color) {
            //if the message is only for one team, check if it is ours
            //xxx: not quite kosher... e.g. if two teams are cooperating, they
            //  may still have different colors, but you'd want them to be able
            //  to see the private parts of each other; but for now nobody cares
            bool show = false;
            auto game = mEngine.singleton!(GameInfo)();
            //xxx it is a bit weird that hud elements using HudElementWidget
            //    are created before GameFrame etc., so stuff like GameInfo
            //    is not neccesarily available
            if (!game)
                return;
            foreach (Team t; game.control.getOwnedTeams()) {
                if (t.theme is msg.color) {
                    show = true;
                    break;
                }
            }
            if (!show)
                return;
        }
        //queue for later display
        mMessages.push(msg);
    }

    override void simulate() {
        if (!mInterp.inProgress && !mMessages.empty) {
            //put new message
            auto curMsg = mMessages.pop();
            text = mLocaleMsg.translateLocalizedMessage(curMsg.lm);
            auto theme = curMsg.color;
            auto p = mStdFont;
            if (theme) {
                p.fore_color = theme.color;
            }
            setFont(p);
            mInterp.init(curMsg.displayTime,
                -containedBorderBounds.p1.y - containedBorderBounds.size.y, 0);
        }
        visible = working;
        setAddToPos(Vector2i(0, mInterp.value()));
    }
}
