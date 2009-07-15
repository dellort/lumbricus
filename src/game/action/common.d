module game.action.common;

import game.action.base;
import game.game;
import game.gobject;
import utils.reflection;
import utils.time;

//waits for some time
void delayAction(ActionContext ctx, Time duration) {
    if (duration == Time.Null)
        return;
    ctx.putObj(new DelayedObj(ctx.engine, duration));
}

//active for a specified time, then dies (for delay action)
class DelayedObj : GameObject {
    private {
        Time mWaitDone;
    }

    this(GameEngine eng, Time duration) {
        super(eng);
        mWaitDone = engine.gameTime.current + duration;
    }
    this(ReflectCtor c) {
        super(c);
    }

    bool activity() {
        return active;
    }

    override void simulate(float deltaT) {
        if (engine.gameTime.current >= mWaitDone)
            kill();
    }
}

static this() {
    regAction!(delayAction, "duration")("delay");
}
