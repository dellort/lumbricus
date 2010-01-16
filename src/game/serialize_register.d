//this module contains calls to register all classes for serialization
//actually, not really "all", but most
module game.serialize_register;

import utils.reflection;

import game.gameshell : serialize_types;

void initGameSerialization() {
    serialize_types = new Types();
    //so yeah, I removed game saving
}
