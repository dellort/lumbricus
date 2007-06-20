module gui.loadingscreen;

import framework.framework;
import framework.font;
import gui.guiobject;
import str = std.string;
import utils.time;
import utils.vector2;

class LoadingScreen : GuiObject {
    Font mFont;
    Vector2i mTxtSize;
    char[] mCurTxt;
    int mCurChunk, mChunkCount;
    bool mLoading, mLoadRes;
    bool delegate(int cur) mLoadDel;
    void delegate() mFinishDel;

    this() {
        mFont = gFramework.fontManager.loadFont("loading");
        mLoading = false;
    }

    private void prog(int cur, int tot) {
        mCurTxt = "Loading... "
            ~str.toString((cur*100)/tot)~"%";
    }

    void simulate(Time curTime, Time deltaT) {
        mCurTxt = "Loading";
        if (mLoading) {
            if (mCurChunk >= mChunkCount || !mLoadRes) {
                finishLoad();
                prog(1,1);
            } else if (mCurChunk >= 0) {
                prog(mCurChunk, mChunkCount);
                mLoadRes = mLoadDel(mCurChunk);
            } else {
                prog(0,1);
            }
            mCurChunk++;
        }
        mTxtSize = mFont.textSize(mCurTxt);
    }

    void draw(Canvas canvas) {
        canvas.drawFilledRect(Vector2i(0,0),canvas.clientSize,Color(0,0,0));
        auto org = scene.size / 2 - mTxtSize / 2;
        mFont.drawText(canvas, org, mCurTxt);
    }

    void resize() {
        //xxx self-managed position (someone said gui-layouter...)
        pos = Vector2i(0);
        size = scene.size;
    }

    void startLoad(int chunkCount, bool delegate(int cur) loadChunk,
        void delegate() loadFinish)
    {
        mLoading = true;
        mLoadRes = true;
        active = true;
        mChunkCount = chunkCount;
        mCurChunk = -1;
        mLoadDel = loadChunk;
        mFinishDel = loadFinish;
    }

    private void finishLoad() {
        mFinishDel();
        mLoading = false;
    }

    bool loading() {
        return mLoading;
    }
}
