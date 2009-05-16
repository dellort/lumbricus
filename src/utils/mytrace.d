module utils.mytrace;

//this code in here is evil, twisted, SLOW, sick, hacky and dangerous
//enable at own risk
//the module will link itself into the Tango runtime using a module ctor
//comment to disable this module
debug version = EnableChainsaw;

const char[] MODULE_PREFIX = "utils/mytrace.d: ";

//the code is Linux specific, but Windows user can use this:
//  http://monsterbrowser.googlecode.com/svn/monsterbrowser/trunk/TangoTrace2.d

private:
version (EnableChainsaw):

version (Tango) version (DigitalMars) version (X86) version (linux) {
    version = EnableDMDLinuxX86;
    //extra hacky and dangerous to enable this
    version = SetSigHandler;
}

version (EnableDMDLinuxX86) {
    import tango.stdc.stdlib;
    import tango.stdc.stdio;
    import tango.stdc.string : strcmp, strlen;
    import tango.stdc.signal;
    import tango.core.stacktrace.StackTrace;
    import tango.core.stacktrace.Demangler;

    //immutable after initialization
    char[] g_str_tab;
    Elf32_Sym[] g_sym_tab;
    Elf32_Sym* g_stop_traceback_at;

    static this() {
        version (SetSigHandler) {
            //random things could happen, especially with multithreading
            pragma(msg, MODULE_PREFIX ~ "hi, I'm very dangerous!");
        }

        if (load_symbols("/proc/self/exe\0")) {
            rt_setSymbolizeFrameInfoFnc(&my_symbolizeFrameInfo);

            version (SetSigHandler) {
                install_sighandlers();
            }

            //in some situations, libc backtrace (used by Tango) fails
            //here's a DMD/Phobos based frame walker
            //rt_setAddrBacktraceFnc(&dmd_AddrBacktrace);
            //g_stop_traceback_at = sym_find_by_name("_Dmain");
        }
    }

    static this() {
        //missing in tango
        internalFuncs["rt_addrBacktrace"] = 1;
        internalFuncs["rt_createTraceContext"] = 1;
    }

    bool my_symbolizeFrameInfo(ref Exception.FrameInfo info,
        TraceContext* context, char[] buf)
    {
        Elf32_Sym* psym = sym_find_by_address(info.address);
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

    alias ushort Elf32_Half;
    alias uint Elf32_Addr;
    alias uint Elf32_Off;
    alias int Elf32_Sword;
    alias int Elf32_Word;

    struct Elf32_Ehdr {
        align(1):
        uint e_ident1;
        uint e_ident2;
        uint e_ident3;
        uint e_ident4;
        Elf32_Half e_type;
        Elf32_Half e_machine;
        Elf32_Word e_version;
        Elf32_Addr e_entry;
        Elf32_Off e_phoff;
        Elf32_Off e_shoff;
        Elf32_Word e_flags;
        Elf32_Half e_ehsize;
        Elf32_Half e_phentsize;
        Elf32_Half e_phnum;
        Elf32_Half e_shentsize;
        Elf32_Half e_shnum;
        Elf32_Half e_shstrndx;
    }
    struct Elf32_Shdr {
        align(1):
        Elf32_Word sh_name;
        Elf32_Word sh_type;
        Elf32_Word sh_flags;
        Elf32_Addr sh_addr;
        Elf32_Off sh_offset;
        Elf32_Word sh_size;
        Elf32_Word sh_link;
        Elf32_Word sh_info;
        Elf32_Word sh_addralign;
        Elf32_Word sh_entsize;
    }
    struct Elf32_Sym {
        align(1):
        Elf32_Word st_name;
        Elf32_Addr st_value;
        Elf32_Word st_size;
        char st_info;
        char st_other;
        Elf32_Half st_shndx;
    }

    enum {
        SHT_SYMTAB = 2,
        SHT_STRTAB = 3,
    }

    bool load_symbols(char* me) {
        void readblock(FILE* file, int offset, void* ptr, size_t size) {
            if (!size)
                return;

            fseek(file, offset, SEEK_SET);
            if (fread(ptr, size, 1, file) != 1) {
                fprintf(stderr, "%.*sUnable to read ELF file\n", MODULE_PREFIX);
                abort();
            }
        }

        FILE* elf = fopen(me, "rb");
        if (!elf)
            return false;

        scope(exit) fclose(elf);

        Elf32_Ehdr header;
        readblock(elf, 0, &header, header.sizeof);
        if (header.e_ident1 != 0x46_4C_45_7F) //"\x7fELF"
            return false;

        //find .symtab
        //on DMD/Linux, .symtab is mostly near the end of the section table
        //so... search backwards
        //if no .symtab is found, symtab_section will contain the NULL section
        Elf32_Shdr symtab_section;
        for (int n = header.e_shnum - 1; n >= 0; n--) {
            readblock(elf, header.e_shoff + header.e_shentsize * n,
                &symtab_section, symtab_section.sizeof);
            if (symtab_section.sh_type == SHT_SYMTAB)
                break;
        }

        Elf32_Shdr strtab_section;
        readblock(elf, header.e_shoff
            + header.e_shentsize * symtab_section.sh_link,
            &strtab_section, strtab_section.sizeof);

        g_str_tab.length = strtab_section.sh_size;
        readblock(elf, strtab_section.sh_offset, g_str_tab.ptr,
            g_str_tab.length);

        g_sym_tab.length = symtab_section.sh_size / Elf32_Sym.sizeof;
        readblock(elf, symtab_section.sh_offset, g_sym_tab.ptr,
            Elf32_Sym.sizeof * g_sym_tab.length);

        return true;
    }

    Elf32_Sym* sym_find_by_address(Elf32_Addr addr) {
        for (int n = 0; n < g_sym_tab.length; n++) {
            Elf32_Sym* sym = &g_sym_tab[n];
            if (sym_contains_address(sym, addr))
                return sym;
        }
        return null;
    }

    bool sym_contains_address(Elf32_Sym* psym, Elf32_Addr addr) {
        if (!psym)
            return false;
        return (addr >= psym.st_value && addr < psym.st_value + psym.st_size)
                || (addr == psym.st_value);
    }

    Elf32_Sym* sym_find_by_name(char* name) {
        for (int n = 0; n < g_sym_tab.length; n++) {
            Elf32_Sym* sym = &g_sym_tab[n];
            if (!strcmp(&g_str_tab[sym.st_name], name))
                return sym;
        }
        return null;
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

            if (sym_contains_address(g_stop_traceback_at, retaddr))
                break;
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

    //trace on signal

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

        //somehow it seems Tango doesn't want to output the backtrace
        //so do it manually
        //info.writeOut((char[] s) { fprintf(stderr, "%.*", s); });
        foreach (Exception.FrameInfo f; info) {
            my_symbolizeFrameInfo(f, null, null);
            fprintf(stderr, "%.*s\n", f.func);
        }

        fprintf(stderr, "%.*sabort().\n", MODULE_PREFIX);
        abort();
    }

    void install_sighandlers() {
        //add whatever signal barked at you
        signal(SIGSEGV, &signal_handler);
        signal(SIGFPE, &signal_handler);
    }
}
