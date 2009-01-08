/*
    Copyright (C) 2005-2007 Christopher E. Miller

    This software is provided 'as-is', without any express or implied
    warranty.  In no event will the authors be held liable for any damages
    arising from the use of this software.

    Permission is granted to anyone to use this software for any purpose,
    including commercial applications, and to alter it and redistribute it
    freely, subject to the following restrictions:

    1. The origin of this software must not be misrepresented; you must not
       claim that you wrote the original software. If you use this software
       in a product, an acknowledgment in the product documentation would be
       appreciated but is not required.
    2. Altered source versions must be plainly marked as such, and must not be
       misrepresented as being the original software.
    3. This notice may not be removed or altered from any source distribution.
*/
module irclib.tools;


version(Tango)
{
    bool ilCharisdigit(dchar ch)
    {
        return ch >= '0' && ch <= '9';
    }
}
else
{
    import std.ctype;

    alias std.ctype.isdigit ilCharisdigit;
}


/// Flags for specifying types of IRC control codes.
enum ControlCodes
{
    NONE = 0, /// No flags specified.

    COLOR = 0x1, ///
    BOLD = 0x2, ///
    UNDERLINE = 0x4, ///
    REVERSE = 0x8, ///

    PLAIN = 0x10, ///

    CTCP = 0x20, ///

    ALL = COLOR | BOLD | UNDERLINE | REVERSE | PLAIN | CTCP, /// All of the above.
}


/// _Strip _codes from the string. _Strips all _codes by default.
char[] strip(char[] s, ControlCodes codes = ControlCodes.ALL)
{
    char* presult = null;
    size_t riw = 0; // Result index.
    size_t iw;


    void initResult()
    {
        if(!presult)
        {
            presult = (new char[s.length]).ptr;
            presult[0 .. iw] = s[0 .. iw];
            riw = iw;
        }
    }


    for(iw = 0; iw != s.length; iw++)
    {
        inner_strip:
        switch(s[iw])
        {
            case 3: // Color.
                if(codes & ControlCodes.COLOR)
                {
                    initResult();

                    iw++;
                    if(iw == s.length)
                        goto done_stripping;
                    if(!ilCharisdigit(s[iw]))
                        goto inner_strip;

                    iw++;
                    if(iw == s.length)
                        goto done_stripping;
                    if(!ilCharisdigit(s[iw]))
                    {
                        if(s[iw] != ',')
                            goto inner_strip;

                        iw++;
                        if(iw == s.length)
                            goto done_stripping;
                        if(!ilCharisdigit(s[iw]))
                            goto inner_strip;

                        iw++;
                        if(iw == s.length)
                            goto done_stripping;
                        if(!ilCharisdigit(s[iw]))
                            goto inner_strip;
                    }

                    iw++;
                    if(iw == s.length)
                        goto done_stripping;
                    if(s[iw] == ',')
                    {
                        iw++;
                        if(iw == s.length)
                            goto done_stripping;
                        if(!ilCharisdigit(s[iw]))
                            goto inner_strip;

                        iw++;
                        if(iw == s.length)
                            goto done_stripping;
                        if(!ilCharisdigit(s[iw]))
                            goto inner_strip;
                    }
                    else
                    {
                        goto inner_strip;
                    }

                    continue;
                }
                break;

            case 2: // Bold.
                if(codes & ControlCodes.BOLD)
                {
                    initResult();
                    continue;
                }
                break;

            case 31: // Underline.
                if(codes & ControlCodes.UNDERLINE)
                {
                    initResult();
                    continue;
                }
                break;

            case 22: // Reverse.
                if(codes & ControlCodes.REVERSE)
                {
                    initResult();
                    continue;
                }
                break;

            case 1: // CTCP.
                if(codes & ControlCodes.CTCP)
                {
                    initResult();
                    continue;
                }
                break;

            case 15: // Plain text.
                if(codes & ControlCodes.PLAIN)
                {
                    initResult();
                    continue;
                }
                break;

            default: ;
        }

        if(presult)
            presult[riw++] = s[iw];
    }
    done_stripping:

    if(!presult)
        return s;
    return presult[0 .. riw];
}

