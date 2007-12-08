//dependency hack (to avoid the forward referenced enum error)
module framework.enums;

enum Transparency {
    None,
    Colorkey,
    Alpha,
    AutoDetect, //special value: get transparency from file when loading
                //invalid as surface transparency type
}
