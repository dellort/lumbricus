module framework.keysyms;

enum Keycode {
    INVALID,
    BACKSPACE,
    TAB,
    CLEAR,
    RETURN,
    PAUSE,
    ESCAPE,
    SPACE,
    EXCLAIM,
    QUOTEDBL,
    HASH,
    DOLLAR,
    AMPERSAND,
    QUOTE,
    LEFTPAREN,
    RIGHTPAREN,
    ASTERISK,
    PLUS,
    COMMA,
    MINUS,
    PERIOD,
    SLASH,
    N0,
    N1,
    N2,
    N3,
    N4,
    N5,
    N6,
    N7,
    N8,
    N9,
    COLON,
    SEMICOLON,
    LESS,
    EQUALS,
    GREATER,
    QUESTION,
    AT,
    LEFTBRACKET,
    BACKSLASH,
    RIGHTBRACKET,
    CARET,
    UNDERSCORE,
    BACKQUOTE,
    A,
    B,
    C,
    D,
    E,
    F,
    G,
    H,
    I,
    J,
    K,
    L,
    M,
    N,
    O,
    P,
    Q,
    R,
    S,
    T,
    U,
    V,
    W,
    X,
    Y,
    Z,
    DELETE,
    WORLD_0,
    WORLD_1,
    WORLD_2,
    WORLD_3,
    WORLD_4,
    WORLD_5,
    WORLD_6,
    WORLD_7,
    WORLD_8,
    WORLD_9,
    WORLD_10,
    WORLD_11,
    WORLD_12,
    WORLD_13,
    WORLD_14,
    WORLD_15,
    WORLD_16,
    WORLD_17,
    WORLD_18,
    WORLD_19,
    WORLD_20,
    WORLD_21,
    WORLD_22,
    WORLD_23,
    WORLD_24,
    WORLD_25,
    WORLD_26,
    WORLD_27,
    WORLD_28,
    WORLD_29,
    WORLD_30,
    WORLD_31,
    WORLD_32,
    WORLD_33,
    WORLD_34,
    WORLD_35,
    WORLD_36,
    WORLD_37,
    WORLD_38,
    WORLD_39,
    WORLD_40,
    WORLD_41,
    WORLD_42,
    WORLD_43,
    WORLD_44,
    WORLD_45,
    WORLD_46,
    WORLD_47,
    WORLD_48,
    WORLD_49,
    WORLD_50,
    WORLD_51,
    WORLD_52,
    WORLD_53,
    WORLD_54,
    WORLD_55,
    WORLD_56,
    WORLD_57,
    WORLD_58,
    WORLD_59,
    WORLD_60,
    WORLD_61,
    WORLD_62,
    WORLD_63,
    WORLD_64,
    WORLD_65,
    WORLD_66,
    WORLD_67,
    WORLD_68,
    WORLD_69,
    WORLD_70,
    WORLD_71,
    WORLD_72,
    WORLD_73,
    WORLD_74,
    WORLD_75,
    WORLD_76,
    WORLD_77,
    WORLD_78,
    WORLD_79,
    WORLD_80,
    WORLD_81,
    WORLD_82,
    WORLD_83,
    WORLD_84,
    WORLD_85,
    WORLD_86,
    WORLD_87,
    WORLD_88,
    WORLD_89,
    WORLD_90,
    WORLD_91,
    WORLD_92,
    WORLD_93,
    WORLD_94,
    WORLD_95,
    KP0,
    KP1,
    KP2,
    KP3,
    KP4,
    KP5,
    KP6,
    KP7,
    KP8,
    KP9,
    KP_PERIOD,
    KP_DIVIDE,
    KP_MULTIPLY,
    KP_MINUS,
    KP_PLUS,
    KP_ENTER,
    KP_EQUALS,
    UP,
    DOWN,
    RIGHT,
    LEFT,
    INSERT,
    HOME,
    END,
    PAGEUP,
    PAGEDOWN,
    F1,
    F2,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    F10,
    F11,
    F12,
    F13,
    F14,
    F15,
    NUMLOCK,
    CAPSLOCK,
    SCROLLOCK,
    RSHIFT,
    LSHIFT,
    RCTRL,
    LCTRL,
    RALT,
    LALT,
    RMETA,
    LMETA,
    LSUPER,
    RSUPER,
    MODE,
    COMPOSE,
    HELP,
    PRINT,
    SYSREQ,
    BREAK,
    MENU,
    POWER,
    EURO,
    UNDO,

    MOUSE_LEFT,
    MOUSE_MIDDLE,
    MOUSE_RIGHT,
    MOUSE_WHEELUP,
    MOUSE_WHEELDOWN,
    MOUSE_BUTTON6,
    MOUSE_BUTTON7,
    MOUSE_BUTTON8,
    MOUSE_BUTTON9,
    MOUSE_BUTTON10,
    //mice with more than 10 buttons???
}

struct KeycodeToName {
    Keycode code;
    char[] name;
}

const KeycodeToName g_keycode_to_name[] = [
    {Keycode.BACKSPACE, "backspace"},
    {Keycode.TAB, "tab"},
    {Keycode.CLEAR, "clear"},
    {Keycode.RETURN, "return"},
    {Keycode.PAUSE, "pause"},
    {Keycode.ESCAPE, "escape"},
    {Keycode.SPACE, "space"},
    {Keycode.EXCLAIM, "exclaim"},
    {Keycode.QUOTEDBL, "quotedbl"},
    {Keycode.HASH, "hash"},
    {Keycode.DOLLAR, "dollar"},
    {Keycode.AMPERSAND, "ampersand"},
    {Keycode.QUOTE, "quote"},
    {Keycode.LEFTPAREN, "leftparen"},
    {Keycode.RIGHTPAREN, "rightparen"},
    {Keycode.ASTERISK, "asterisk"},
    {Keycode.PLUS, "plus"},
    {Keycode.COMMA, "comma"},
    {Keycode.MINUS, "minus"},
    {Keycode.PERIOD, "period"},
    {Keycode.SLASH, "slash"},
    {Keycode.N0, "0"},
    {Keycode.N1, "1"},
    {Keycode.N2, "2"},
    {Keycode.N3, "3"},
    {Keycode.N4, "4"},
    {Keycode.N5, "5"},
    {Keycode.N6, "6"},
    {Keycode.N7, "7"},
    {Keycode.N8, "8"},
    {Keycode.N9, "9"},
    {Keycode.COLON, "colon"},
    {Keycode.SEMICOLON, "semicolon"},
    {Keycode.LESS, "less"},
    {Keycode.EQUALS, "equals"},
    {Keycode.GREATER, "greater"},
    {Keycode.QUESTION, "question"},
    {Keycode.AT, "at"},
    {Keycode.LEFTBRACKET, "leftbracket"},
    {Keycode.BACKSLASH, "backslash"},
    {Keycode.RIGHTBRACKET, "rightbracket"},
    {Keycode.CARET, "caret"},
    {Keycode.UNDERSCORE, "underscore"},
    {Keycode.BACKQUOTE, "backquote"},
    {Keycode.A, "a"},
    {Keycode.B, "b"},
    {Keycode.C, "c"},
    {Keycode.D, "d"},
    {Keycode.E, "e"},
    {Keycode.F, "f"},
    {Keycode.G, "g"},
    {Keycode.H, "h"},
    {Keycode.I, "i"},
    {Keycode.J, "j"},
    {Keycode.K, "k"},
    {Keycode.L, "l"},
    {Keycode.M, "m"},
    {Keycode.N, "n"},
    {Keycode.O, "o"},
    {Keycode.P, "p"},
    {Keycode.Q, "q"},
    {Keycode.R, "r"},
    {Keycode.S, "s"},
    {Keycode.T, "t"},
    {Keycode.U, "u"},
    {Keycode.V, "v"},
    {Keycode.W, "w"},
    {Keycode.X, "x"},
    {Keycode.Y, "y"},
    {Keycode.Z, "z"},
    {Keycode.DELETE, "delete"},
    {Keycode.WORLD_0, "world_0"},
    {Keycode.WORLD_1, "world_1"},
    {Keycode.WORLD_2, "world_2"},
    {Keycode.WORLD_3, "world_3"},
    {Keycode.WORLD_4, "world_4"},
    {Keycode.WORLD_5, "world_5"},
    {Keycode.WORLD_6, "world_6"},
    {Keycode.WORLD_7, "world_7"},
    {Keycode.WORLD_8, "world_8"},
    {Keycode.WORLD_9, "world_9"},
    {Keycode.WORLD_10, "world_10"},
    {Keycode.WORLD_11, "world_11"},
    {Keycode.WORLD_12, "world_12"},
    {Keycode.WORLD_13, "world_13"},
    {Keycode.WORLD_14, "world_14"},
    {Keycode.WORLD_15, "world_15"},
    {Keycode.WORLD_16, "world_16"},
    {Keycode.WORLD_17, "world_17"},
    {Keycode.WORLD_18, "world_18"},
    {Keycode.WORLD_19, "world_19"},
    {Keycode.WORLD_20, "world_20"},
    {Keycode.WORLD_21, "world_21"},
    {Keycode.WORLD_22, "world_22"},
    {Keycode.WORLD_23, "world_23"},
    {Keycode.WORLD_24, "world_24"},
    {Keycode.WORLD_25, "world_25"},
    {Keycode.WORLD_26, "world_26"},
    {Keycode.WORLD_27, "world_27"},
    {Keycode.WORLD_28, "world_28"},
    {Keycode.WORLD_29, "world_29"},
    {Keycode.WORLD_30, "world_30"},
    {Keycode.WORLD_31, "world_31"},
    {Keycode.WORLD_32, "world_32"},
    {Keycode.WORLD_33, "world_33"},
    {Keycode.WORLD_34, "world_34"},
    {Keycode.WORLD_35, "world_35"},
    {Keycode.WORLD_36, "world_36"},
    {Keycode.WORLD_37, "world_37"},
    {Keycode.WORLD_38, "world_38"},
    {Keycode.WORLD_39, "world_39"},
    {Keycode.WORLD_40, "world_40"},
    {Keycode.WORLD_41, "world_41"},
    {Keycode.WORLD_42, "world_42"},
    {Keycode.WORLD_43, "world_43"},
    {Keycode.WORLD_44, "world_44"},
    {Keycode.WORLD_45, "world_45"},
    {Keycode.WORLD_46, "world_46"},
    {Keycode.WORLD_47, "world_47"},
    {Keycode.WORLD_48, "world_48"},
    {Keycode.WORLD_49, "world_49"},
    {Keycode.WORLD_50, "world_50"},
    {Keycode.WORLD_51, "world_51"},
    {Keycode.WORLD_52, "world_52"},
    {Keycode.WORLD_53, "world_53"},
    {Keycode.WORLD_54, "world_54"},
    {Keycode.WORLD_55, "world_55"},
    {Keycode.WORLD_56, "world_56"},
    {Keycode.WORLD_57, "world_57"},
    {Keycode.WORLD_58, "world_58"},
    {Keycode.WORLD_59, "world_59"},
    {Keycode.WORLD_60, "world_60"},
    {Keycode.WORLD_61, "world_61"},
    {Keycode.WORLD_62, "world_62"},
    {Keycode.WORLD_63, "world_63"},
    {Keycode.WORLD_64, "world_64"},
    {Keycode.WORLD_65, "world_65"},
    {Keycode.WORLD_66, "world_66"},
    {Keycode.WORLD_67, "world_67"},
    {Keycode.WORLD_68, "world_68"},
    {Keycode.WORLD_69, "world_69"},
    {Keycode.WORLD_70, "world_70"},
    {Keycode.WORLD_71, "world_71"},
    {Keycode.WORLD_72, "world_72"},
    {Keycode.WORLD_73, "world_73"},
    {Keycode.WORLD_74, "world_74"},
    {Keycode.WORLD_75, "world_75"},
    {Keycode.WORLD_76, "world_76"},
    {Keycode.WORLD_77, "world_77"},
    {Keycode.WORLD_78, "world_78"},
    {Keycode.WORLD_79, "world_79"},
    {Keycode.WORLD_80, "world_80"},
    {Keycode.WORLD_81, "world_81"},
    {Keycode.WORLD_82, "world_82"},
    {Keycode.WORLD_83, "world_83"},
    {Keycode.WORLD_84, "world_84"},
    {Keycode.WORLD_85, "world_85"},
    {Keycode.WORLD_86, "world_86"},
    {Keycode.WORLD_87, "world_87"},
    {Keycode.WORLD_88, "world_88"},
    {Keycode.WORLD_89, "world_89"},
    {Keycode.WORLD_90, "world_90"},
    {Keycode.WORLD_91, "world_91"},
    {Keycode.WORLD_92, "world_92"},
    {Keycode.WORLD_93, "world_93"},
    {Keycode.WORLD_94, "world_94"},
    {Keycode.WORLD_95, "world_95"},
    {Keycode.KP0, "kp0"},
    {Keycode.KP1, "kp1"},
    {Keycode.KP2, "kp2"},
    {Keycode.KP3, "kp3"},
    {Keycode.KP4, "kp4"},
    {Keycode.KP5, "kp5"},
    {Keycode.KP6, "kp6"},
    {Keycode.KP7, "kp7"},
    {Keycode.KP8, "kp8"},
    {Keycode.KP9, "kp9"},
    {Keycode.KP_PERIOD, "kp_period"},
    {Keycode.KP_DIVIDE, "kp_divide"},
    {Keycode.KP_MULTIPLY, "kp_multiply"},
    {Keycode.KP_MINUS, "kp_minus"},
    {Keycode.KP_PLUS, "kp_plus"},
    {Keycode.KP_ENTER, "kp_enter"},
    {Keycode.KP_EQUALS, "kp_equals"},
    {Keycode.UP, "up"},
    {Keycode.DOWN, "down"},
    {Keycode.RIGHT, "right"},
    {Keycode.LEFT, "left"},
    {Keycode.INSERT, "insert"},
    {Keycode.HOME, "home"},
    {Keycode.END, "end"},
    {Keycode.PAGEUP, "pageup"},
    {Keycode.PAGEDOWN, "pagedown"},
    {Keycode.F1, "f1"},
    {Keycode.F2, "f2"},
    {Keycode.F3, "f3"},
    {Keycode.F4, "f4"},
    {Keycode.F5, "f5"},
    {Keycode.F6, "f6"},
    {Keycode.F7, "f7"},
    {Keycode.F8, "f8"},
    {Keycode.F9, "f9"},
    {Keycode.F10, "f10"},
    {Keycode.F11, "f11"},
    {Keycode.F12, "f12"},
    {Keycode.F13, "f13"},
    {Keycode.F14, "f14"},
    {Keycode.F15, "f15"},
    {Keycode.NUMLOCK, "numlock"},
    {Keycode.CAPSLOCK, "capslock"},
    {Keycode.SCROLLOCK, "scrollock"},
    {Keycode.RSHIFT, "rshift"},
    {Keycode.LSHIFT, "lshift"},
    {Keycode.RCTRL, "rctrl"},
    {Keycode.LCTRL, "lctrl"},
    {Keycode.RALT, "ralt"},
    {Keycode.LALT, "lalt"},
    {Keycode.RMETA, "rmeta"},
    {Keycode.LMETA, "lmeta"},
    {Keycode.LSUPER, "lsuper"},
    {Keycode.RSUPER, "rsuper"},
    {Keycode.MODE, "mode"},
    {Keycode.COMPOSE, "compose"},
    {Keycode.HELP, "help"},
    {Keycode.PRINT, "print"},
    {Keycode.SYSREQ, "sysreq"},
    {Keycode.BREAK, "break"},
    {Keycode.MENU, "menu"},
    {Keycode.POWER, "power"},
    {Keycode.EURO, "euro"},
    {Keycode.UNDO, "undo"},

    {Keycode.MOUSE_LEFT, "mouse_left"},
    {Keycode.MOUSE_MIDDLE, "mouse_middle"},
    {Keycode.MOUSE_RIGHT, "mouse_right"},
    {Keycode.MOUSE_WHEELUP, "mouse_wheelup"},
    {Keycode.MOUSE_WHEELDOWN, "mouse_wheeldown"},
    {Keycode.MOUSE_BUTTON6, "mouse_btn5"},
    {Keycode.MOUSE_BUTTON7, "mouse_btn6"},
    {Keycode.MOUSE_BUTTON8, "mouse_btn7"},
    {Keycode.MOUSE_BUTTON9, "mouse_btn8"},
    {Keycode.MOUSE_BUTTON10, "mouse_btn9"},
];
