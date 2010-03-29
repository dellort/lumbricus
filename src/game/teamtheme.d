module game.teamtheme;

import common.animation;
import framework.font;
import framework.framework;
import gui.rendertext;
import gui.renderbox;
import common.resset;
import utils.color;
import utils.misc;
import utils.time;


//per-team themeing used by the game engine, by the GUI etc.
//all members are read only after initialization
class TeamTheme {
    Color color;
    int colorIndex; //index into cTeamColors
    Font font, font_flash;

    //wwp hardcodes these colors (there are separate bitmaps for each)
    //the indices are also hardcoded to wwp (0 must be red etc.)
    static const char[][] cTeamColors = [
        "red",
        "blue",
        "green",
        "yellow",
        "magenta",
        "cyan",
    ];

    Animation arrow, pointed, change, cursor, click, aim;

    this(ResourceSet resources, int index) {
        colorIndex = index;
        char[] colorname = cTeamColors[colorIndex];
        color = Color.fromString("team_" ~ colorname); //if it fails, it is messed up

        Animation loadanim(char[] node) {
            Animation ani = resources.get!(Animation)(node ~ "_" ~ name(), true);
            if (!ani)
                ani = resources.get!(Animation)(node);
            return ani;
        }

        arrow = loadanim("darrow");
        pointed = loadanim("pointed");
        change = loadanim("change");
        cursor = loadanim("point");
        click = loadanim("click");
        aim = loadanim("aim");

        font = gFontManager.loadFont("wormfont");
        //set color; Font is immutable
        auto style = font.properties;
        style.fore_color = color;
        font = new Font(style);

        font_flash = gFontManager.loadFont("wormfont_flash");
    }

    //the name used to identify the theme
    //does not anymore equal to color string, see colors.conf
    char[] name() {
        return cTeamColors[colorIndex];
    }

    FormattedText textCreate() {
        auto txt = new FormattedText();
        WormLabels.textApplyWormStyle(txt);
        txt.font = font;
        return txt;
    }
}

//the class is just a namespace
class WormLabels {
    private this() {}

    static BoxProperties textWormBorderStyle() {
        //init to what we had in the GUI in r865
        BoxProperties border;
        border.border = Color(0.7);
        border.back = Color(0,0,0,0.7);
        border.borderWidth = 1;
        border.cornerRadius = 3;
        return border;
    }

    //and some more hacky hacks
    static void textApplyWormStyle(FormattedText txt) {
        txt.setBorder(textWormBorderStyle());
        txt.font = gFontManager.loadFont("wormfont");
    }

    static FormattedText textCreate() {
        auto txt = new FormattedText();
        textApplyWormStyle(txt);
        return txt;
    }

    static Font textFlashFont() {
        //xxx cache this?
        return gFontManager.loadFont("wormfont_flash");
    }
}
