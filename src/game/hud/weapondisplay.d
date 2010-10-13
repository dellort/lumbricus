module game.hud.weapondisplay;

import framework.drawing;
import framework.surface;
import game.controller;
import game.wcontrol;
import game.hud.teaminfo;
import game.weapon.weapon;
import game.weapon.types;
import gui.boxcontainer;
import gui.container;
import gui.global;
import gui.label;
import gui.renderbox;
import gui.widget;
import utils.color;
import utils.time;
import utils.misc;
import utils.vector2;

//stack the controls defined below
class WeaponDisplay : BoxContainer {
    this(GameInfo game) {
        super(false, false, 5);
        add(new WeaponParam(game));
        add(new WeaponIconAmmo(game));
    }
}

//simple fixed icon with text overlay, to show current weapon param
class WeaponParam : SimpleContainer {
    private {
        GameInfo mGame;
        ImageLabel mLblIcon;
        Label mLblParam;
        int mLastParam = -1;
    }

    this(GameInfo game) {
        mGame = game;
        mLblIcon = new ImageLabel();
        mLblIcon.styles.addClass("weapontimer-icon");
        mLblIcon.image = gGuiResources.get!(Surface)("stopwatch_icon");
        add(mLblIcon);
        mLblParam = new Label();
        mLblParam.styles.addClass("weaponparamlabel");
        mLblParam.visible = false;
        auto lay = WidgetLayout.Aligned(1, 1);
        //xxx position text to fit into icon (depends on icon layout)
        lay.padB = Vector2i(12, 3);
        add(mLblParam, lay);
    }

    override void simulate() {
        auto m = mGame.control.getControlledMember;
        Team myTeam;
        WeaponClass curWeapon;
        if (m) {
            myTeam = m.team;
            curWeapon = m.control.mainWeapon();
        }
        //only display if it will be used
        bool hasParam = curWeapon && curWeapon.fireMode.requireParam();

        if (hasParam) {
            int param = curWeapon.fireMode.actualParam(
                m.control.getWeaponParam());
            mLblIcon.visible = true;
            mLblParam.visible = true;
            if (param != mLastParam) {
                mLblParam.setTextFmt(false, "{}", param);
                mLastParam = param;
            }
        } else {
            mLblIcon.visible = false;
            mLblParam.visible = false;
        }
    }
}

//shows the selected weapon, remaining ammo and cooldown time
class WeaponIconAmmo : SimpleContainer {
    private {
        GameInfo mGame;
        ImageLabel mLblWeapon;
        Label mLblAmmo;
        Color mOldColor = Color.Invalid;
        float mCDPercent;
        Time mLastMisfire;
        Color mCDColor = Color.Invalid, mMisfireColor = Color.Invalid;
        int mLastAmmo = -1;

        const cMisfireFlashTime = timeMsecs(250);
    }

    this(GameInfo game) {
        mGame = game;
        mLblWeapon = new ImageLabel();
        mLblWeapon.styles.addClass("weapon-icon");
        mLblWeapon.visible = false;
        add(mLblWeapon);
        mLblAmmo = new Label();
        mLblAmmo.styles.addClass("weaponquantitylabel");
        mLblAmmo.visible = false;
        add(mLblAmmo, WidgetLayout.Aligned(1, 1, Vector2i(2, 2)));

        OnWeaponMisfire.handler(mGame.engine.events, &onMisfire);
    }

    private void onMisfire(WeaponClass sender, WormControl control,
        WeaponMisfireReason reason)
    {
        auto m = mGame.control.getControlledMember;
        if (m.control is control) {
            mLastMisfire = timeCurrentTime();
        }
    }

    //overdraw children with cooldown thingy
    override void onDrawChildren(Canvas canvas) {
        super.onDrawChildren(canvas);
        if (!mCDColor.valid) {
            mCDColor = mLblWeapon.styles.get!(Color)("cooldown-color");
            mMisfireColor = mLblWeapon.styles.get!(Color)("misfire-color");
        }
        if (mLblWeapon.visible) {
            if (mCDPercent > float.epsilon) {
                canvas.drawPercentRect(Vector2i(0), size, mCDPercent, mCDColor);
            }
            if (timeCurrentTime() - mLastMisfire < cMisfireFlashTime) {
                canvas.drawFilledRect(widgetBounds, mMisfireColor);
            }
        }
    }

    override void simulate() {
        auto m = mGame.control.getControlledMember;
        Team myTeam;
        WeaponClass curWeapon;
        if (m) {
            myTeam = m.team;
            curWeapon = m.control.mainWeapon();
        }

        if (myTeam && isLinked) {
            //I assume the color is only used if the label is visible
            auto col = myTeam.color.color;
            if (col != mOldColor) {
                mOldColor = col;
                mLblWeapon.styles.setStyleOverrideT!(Color)("border-color",
                    col);
            }
        }

        if (curWeapon) {
            auto item = myTeam.weapons.find(curWeapon);
            mLblWeapon.visible = true;
            mLblWeapon.image = curWeapon.icon;
            //int p = m.control.getWeaponParam();
            //p = min(p, curWeapon.fireMode.paramTo);
            if (item.quantity != item.cINF) {
                mLblAmmo.visible = true;
                if (item.quantity != mLastAmmo) {
                    mLblAmmo.setTextFmt(false, "x{}", item.quantity);
                    mLastAmmo = item.quantity;
                }
            } else {
                mLblAmmo.visible = false;
            }
            mCDPercent = item.cooldownRemainPerc(mGame.engine);
        } else {
            mLblWeapon.visible = false;
            mLblAmmo.visible = false;
            mCDPercent = 0f;
        }
    }
}
