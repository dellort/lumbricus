module utils.mytrace;

//this code in here is evil, twisted, SLOW, sick, hacky and dangerous
//enable at own risk
//the module will link itself into the Tango runtime using a module ctor
//comment to disable this module
debug version = EnableChainsaw;

//the code is Linux specific, but Windows user can use this:
//  http://monsterbrowser.googlecode.com/svn/monsterbrowser/trunk/TangoTrace2.d

private:
version (EnableChainsaw):

const char[] MODULE_PREFIX = "utils/mytrace.d: ";

version (DigitalMars) version (X86) version (linux) {
    //version = DMD_Backtracer;
}

version (linux) {
    version = ELF_Symbolizer;
}

version (linux) {
    //extra hacky and dangerous to enable this
    version = SetSigHandler;
}


import tango.stdc.stdlib;
import tango.stdc.stdio;
import tango.stdc.string : strcmp, strlen;

import tango.core.stacktrace.StackTrace;
import tango.core.stacktrace.Demangler;


version (ELF_Symbolizer) {
    //immutable after initialization
    char[] g_str_tab;
    Elf_Sym[] g_sym_tab;
    Elf_Sym* g_stop_traceback_at;

    static this() {
        if (load_symbols("/proc/self/exe\0")) {
            rt_setSymbolizeFrameInfoFnc(&my_symbolizeFrameInfo);

            //should be in Tango IMO
            g_stop_traceback_at = sym_find_by_name("_Dmain");

            //missing in tango
            internalFuncs["rt_addrBacktrace"] = 1;
            internalFuncs["rt_createTraceContext"] = 1;
        } else {
            fprintf(stderr, "%.*sLoading symbols from /proc/self failed.\n",
                MODULE_PREFIX);
        }
    }

    bool my_symbolizeFrameInfo(ref Exception.FrameInfo info,
        TraceContext* context, char[] buf)
    {
        Elf_Sym* psym = sym_find_by_address(info.address);
        if (!psym)
            return false;

        ptrdiff_t offset = info.address - psym.st_value;
        //info.offsetSymb = offset; //I have no idea if this is correct
        char* pname = &g_str_tab[psym.st_name];
        char[] name = pname[0..strlen(pname)];

        auto lookup = name;
        //on Linux, dmd-produced symbols always start with "_D"?
        if (lookup.length >= 2 && lookup[0..2] == "_D")
            lookup = name[1..$];
        info.internalFunction = !!(lookup in internalFuncs);

        name = demangler.demangle(name);
        info.func = name;

        return true;
    }

    //-- mini ELF bindings

    alias size_t Elf_Addr;
    alias size_t Elf_Off;
    alias ushort Elf_Half;
    alias int Elf_Sword;
    alias uint Elf_Word;
    alias size_t Elf_Xword; //Elf32 actually uses Elf32_Word instead of this

    version (X86) {
        struct Elf_Sym {
            Elf_Word st_name;
            Elf_Addr st_value;
            Elf_Word st_size;
            char st_info;
            char st_other;
            Elf_Half st_shndx;
        }
    } else version (X86_64) {
        alias ushort Elf_Section;

        struct Elf_Sym {
            Elf_Word st_name;
            char st_info;
            char st_other;
            Elf_Section st_shndx;
            Elf_Addr st_value;
            Elf_Xword st_size;
        }
    } else {
        static assert(false);
    }

    struct Elf_Ehdr {
        uint e_ident1;
        uint e_ident2;
        uint e_ident3;
        uint e_ident4;
        Elf_Half e_type;
        Elf_Half e_machine;
        Elf_Word e_version;
        Elf_Addr e_entry;
        Elf_Off e_phoff;
        Elf_Off e_shoff;
        Elf_Word e_flags;
        Elf_Half e_ehsize;
        Elf_Half e_phentsize;
        Elf_Half e_phnum;
        Elf_Half e_shentsize;
        Elf_Half e_shnum;
        Elf_Half e_shstrndx;
    }
    struct Elf_Shdr {
        Elf_Word sh_name;
        Elf_Word sh_type;
        Elf_Xword sh_flags;
        Elf_Addr sh_addr;
        Elf_Off sh_offset;
        Elf_Xword sh_size;
        Elf_Word sh_link;
        Elf_Word sh_info;
        Elf_Xword sh_addralign;
        Elf_Xword sh_entsize;
    }

    enum {
        SHT_SYMTAB = 2,
        SHT_STRTAB = 3,
    }


    bool load_symbols(char* me) {
        bool readblock(FILE* file, int offset, void* ptr, size_t size) {
            if (!size)
                return true;

            fseek(file, offset, SEEK_SET);
            if (fread(ptr, size, 1, file) != 1) {
                fprintf(stderr, "%.*sUnable to read ELF file\n", MODULE_PREFIX);
                return false;
            }

            return true;
        }

        FILE* elf = fopen(me, "rb");
        if (!elf)
            return false;

        scope(exit) fclose(elf);

        Elf_Ehdr header;
        if (!readblock(elf, 0, &header, header.sizeof))
            return false;
        if (header.e_ident1 != 0x46_4C_45_7F) //"\x7fELF"
            return false;

        //find .symtab
        //on DMD/Linux, .symtab is mostly near the end of the section table
        //so... search backwards
        //if no .symtab is found, symtab_section will contain the NULL section
        Elf_Shdr symtab_section;
        for (int n = header.e_shnum - 1; n >= 0; n--) {
            if (!readblock(elf, header.e_shoff + header.e_shentsize * n,
                &symtab_section, symtab_section.sizeof))
                return false;
            if (symtab_section.sh_type == SHT_SYMTAB)
                break;
        }

        Elf_Shdr strtab_section;
        if (!readblock(elf, header.e_shoff
            + header.e_shentsize * symtab_section.sh_link,
            &strtab_section, strtab_section.sizeof))
            return false;

        g_str_tab.length = strtab_section.sh_size;
        if (!readblock(elf, strtab_section.sh_offset, g_str_tab.ptr,
            g_str_tab.length))
        {
            g_str_tab = null;
            return false;
        }

        g_sym_tab.length = symtab_section.sh_size / Elf_Sym.sizeof;
        if (!readblock(elf, symtab_section.sh_offset, g_sym_tab.ptr,
            Elf_Sym.sizeof * g_sym_tab.length))
        {
            g_str_tab = null;
            g_sym_tab = null;
            return false;
        }

        return true;
    }

    Elf_Sym* sym_find_by_address(Elf_Addr addr) {
        for (int n = 0; n < g_sym_tab.length; n++) {
            Elf_Sym* sym = &g_sym_tab[n];
            if (sym_contains_address(sym, addr))
                return sym;
        }
        return null;
    }

    bool sym_contains_address(Elf_Sym* psym, Elf_Addr addr) {
        if (!psym)
            return false;
        return (addr >= psym.st_value && addr < psym.st_value + psym.st_size)
                || (addr == psym.st_value);
    }

    Elf_Sym* sym_find_by_name(char* name) {
        for (int n = 0; n < g_sym_tab.length; n++) {
            Elf_Sym* sym = &g_sym_tab[n];
            if (!strcmp(&g_str_tab[sym.st_name], name))
                return sym;
        }
        return null;
    }
}

version (DMD_Backtracer) {
    static this() {
        //in some situations, libc backtrace (used by Tango) fails
        //here's a DMD/Phobos based frame walker
        rt_setAddrBacktraceFnc(&dmd_AddrBacktrace);
    }

    size_t dmd_AddrBacktrace(TraceContext* context, TraceContext* contextOut,
        size_t* trace_buf, size_t buf_length, int* flags)
    {
        size_t depth;
        size_t regebp;

        asm {
            mov regebp, EBP ;
        }

        for (;;) {
            size_t retaddr;
            regebp = dmd__eh_find_caller(regebp, &retaddr);

            if (!regebp)
                break;

            if (depth == buf_length)
                break;

            trace_buf[depth] = retaddr;

            depth++;

            //if (sym_contains_address(g_stop_traceback_at, retaddr))
              //  break;
        }

        return depth;
    }

    //borrowed from Phobos' internal/deh2.d
    //slightly modified (uint -> size_t, comments, abort())
    //license is a BSD something
    size_t dmd__eh_find_caller(size_t regbp, size_t *pretaddr) {
        size_t bp = *cast(size_t*)regbp;

        if (bp) {
            if (bp <= regbp) {
                //fprintf(stderr, "%.*sbacktrace error, stop.\n", MODULE_PREFIX);
                //abort();
                return 0;
            }
            *pretaddr = *cast(size_t*)(regbp + size_t.sizeof);
        }

        return bp;
    }
}

//trace on signal
version (SetSigHandler) {
    import tango.stdc.signal;

    static this() {
        //because it's dangerous and bound to cause problems
        //random things could happen, especially with multithreading
        fprintf(stderr, "%.*sWARNING: registering signal handlers for "
            "backtrace!\n", MODULE_PREFIX);

        //add whatever signal barked at you
        signal(SIGSEGV, &signal_handler);
        signal(SIGFPE, &signal_handler);
    }

    extern(C) void signal_handler(int sig) {
        char[] signame;
        switch (sig) {
            case SIGSEGV: signame = "SIGSEGV"; break;
            case SIGFPE: signame = "SIGFPE"; break;
            default:
                signame = "unknown, add to signal_handler()";
        }
        fprintf(stderr, "%.*sSignal caught: %.*s\n", MODULE_PREFIX, signame);

        Exception.TraceInfo info = basicTracer();

        fprintf(stderr, "Backtrace:\n");
        info.writeOut((char[] s) { fprintf(stderr, "%.*s", s); });

        fprintf(stderr, "%.*sabort().\n", MODULE_PREFIX);
        abort();
    }
}
