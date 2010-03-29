module game.controller_events;

import framework.i18n; //for LocalizedMessage
import game.controller;
import game.core;
import game.events;

///let the client display a message (like it's done on round's end etc.)
///this is a bit complicated because message shall be translated on the
///client (i.e. one client might prefer Klingon, while the other is used
///to Latin); so msgid and args are passed to the translation functions
///this returns a value, that is incremented everytime a new message is
///available
///a random int is passed along, so all clients with the same locale
///will select the same message
struct GameMessage {
    LocalizedMessage lm;
    Team actor;     //who did the action (for message color), null for neutral
    bool is_private;//who should see it (only players with Team actor
                    //  in getOwnedTeams() see the message), false for all
}

alias DeclareEvent!("game_message", GameObject, GameMessage) OnGameMessage;


