module game.gui.loadingscreen;

import framework.framework;
import framework.font;
import game.loader;
import gui.widget;
import str = std.string;
import utils.time;
import utils.vector2;

class LoadingScreen : GuiObjectOwnerDrawn {
    private {
        Font mFont;
        Vector2i mTxtSize;
        char[] mCurTxt;
        int mCurChunk;
        bool mLoading, mLoadRes;
        Loader mLoader;
    }

    this() {
        mFont = gFramework.fontManager.loadFont("loading");
        mLoading = false;
    }

    private void prog(int cur, int tot) {
        mCurTxt = "Loading... "
            ~str.toString((cur*100)/tot)~"%";
    }

    override void simulate(Time curTime, Time deltaT) {
        mCurTxt = "Loading";
        if (mLoading) {
            if (mCurChunk >= mLoader.chunkCount || !mLoadRes) {
                finishLoad();
                prog(1,1);
            } else if (mCurChunk >= 0) {
                prog(mCurChunk, mLoader.chunkCount);
                mLoadRes = mLoader.load(mCurChunk);
            } else {
                prog(0,1);
            }
            mCurChunk++;
        }
        mTxtSize = mFont.textSize(mCurTxt);
    }

    void draw(Canvas canvas) {
        canvas.drawFilledRect(Vector2i(0,0),canvas.clientSize,Color(0,0,0));
        auto org = size / 2 - mTxtSize / 2;
        mFont.drawText(canvas, org, mCurTxt);
    }

    void relayout() {
        //xxx self-managed position (someone said gui-layouter...)
        //pos = Vector2i(0);
        //size = scene.size;
    }

    void startLoad(Loader load) {
        mLoading = true;
        mLoadRes = true;
        //active = true;
        mLoader = load;
        mCurChunk = -1;
    }

    private void finishLoad() {
        mLoader.finished();
        mLoading = false;
    }

    bool loading() {
        return mLoading;
    }
}
