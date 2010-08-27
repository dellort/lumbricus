module game.hud.weapondisplay;

import framework.framework;
import framework.font;
import game.controller;
import game.wcontrol;
import game.hud.teaminfo;
import game.weapon.weapon;
import game.weapon.types;
import gui.container;
import gui.label;
import gui.renderbox;
import gui.widget;
import utils.time;
import utils.misc;
import utils.vector2;

//shows the selected weapon, remaining ammo and cooldown time
class WeaponDisplay : SimpleContainer {
    private {
        GameInfo mGame;
        ImageLabel mLblWeapon;
        Label mLblParam;
        Color mOldColor = Color.Invalid;
        float mCDPercent;
        Time mLastMisfire;
        Color mCDColor = Color.Invalid, mMisfireColor = Color.Invalid;

        const cMisfireFlashTime = timeMsecs(250);
    }

    this(GameInfo game) {
        mGame = game;
        mLblWeapon = new ImageLabel();
        mLblWeapon.styles.addClass("weapon-icon");
        mLblWeapon.visible = false;
        add(mLblWeapon);
        mLblParam = new Label();
        mLblParam.styles.addClass("weaponquantitylabel");
        mLblParam.visible = false;
        add(mLblParam, WidgetLayout.Aligned(1, 1, Vector2i(2, 2)));

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
                mLblParam.visible = true;
                mLblParam.setTextFmt(false, "x{}", item.quantity);
            } else {
                mLblParam.visible = false;
            }
            mCDPercent = item.cooldownRemainPerc(mGame.engine);
        } else {
            mLblWeapon.visible = false;
            mLblParam.visible = false;
            mCDPercent = 0f;
        }
    }
}
