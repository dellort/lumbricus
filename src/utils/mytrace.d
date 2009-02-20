module utils.mytrace;

//this code in here is evil, twisted, SLOW, sick, hacky and dangerous
//enable at own risk
//the module will link itself into the Tango runtime using a module ctor
debug version = EnableChainsaw;

//gets cut after this number of entries in the backtrace
const cMaxBacktrace = 30;
//buffer used when formatting output
const cBacktraceLineBuffer = 120;

//the code is Linux specific, but Windows user can use this:
//  http://monsterbrowser.googlecode.com/svn/monsterbrowser/trunk/TangoTrace2.d

private:
version (EnableChainsaw):

version (Tango) version (DigitalMars) version (X86) version (linux) {
    version = EnableDMDLinuxX86;
    //extra hacky and dangerous to enable this
    version = SetSigHandler;
    //Tango doesn't have a demangler, so you may want to disable this
    version = Demangler;
}

version (EnableDMDLinuxX86) {
    import runtime = tango.core.Runtime;
    import tango.text.convert.Layout;
    import tango.stdc.stdlib;
    import tango.stdc.stdio;
    import tango.stdc.string : strcmp, strlen;
    import tango.stdc.signal;
    version (Demangler) import demangler = stdx.demangle;

    Layout!(char) convert;
    Elf32_Sym* stop_traceback_at;

    struct TraceRecord {
        //if depth == cInvalidDepth, it means incomplete backtrace hurrrrr
        const cInvalidDepth = uint.max;
        uint depth;
        size_t ebp;
        //can be used to find an Elf32_Sym
        size_t address;
    }

    static this() {
        pragma(msg, "hi, I'm not multithreading safe!");

        convert = new typeof(convert)();

        if (load_symbols("/proc/self/exe\0")) {
            stop_traceback_at = sym_find_by_name("_Dmain");
            //actually, the runtime calls this function when an Exception is
            //thrown the default handler does nothing (just returns null)
            runtime.Runtime.traceHandler = &myTraceHandler;
            install_sighandlers();
            printf("mytrace.d: loaded and exception/trace handler installed\n");
        }
    }

    Exception.TraceInfo myTraceHandler(void* ptr = null) {
        return new MyTraceInfo();
    }

    class MyTraceInfo : Exception.TraceInfo {
        TraceRecord[cMaxBacktrace] storage;
        TraceRecord[] info;

        this() {
            info = do_backtrace(storage);
        }

        override int opApply(int delegate(inout char[]) dg) {
            foreach (ref record; info) {
                char[cBacktraceLineBuffer] buffer;
                auto txt = printTraceRecord(buffer, record);
                auto res = dg(txt);
                if (res)
                    return res;
            }
            return 0;
        }

        override char[] toString() {
            return "hier koennte ihre werbung stehen";
        }
    }

    struct SPrint {
        Layout!(char) convert;
        bool dynalloc;
        char[] storage;
        char[] output;
        uint write(char[] str) {
            if (dynalloc) {
                output ~= str;
                return str.length;
            }
            if (output.length < storage.length) {
                size_t pos = output.length;
                size_t max = storage.length;
                size_t npos = pos + str.length;
                npos = npos > max ? max : npos;
                storage[pos..npos] = str[0..npos-pos];
                output = storage[0..npos];
            }
            return str.length;
        }
        void opCall(T...)(T args) {
            convert.convert(&write, args);
        }
    }

    //    n caller_address-offset_to_start<tab> unmangled
    //storage: buffer used for formatting; but demangle will alloc memory anyway
    char[] printTraceRecord(char[] storage, ref TraceRecord info,
        bool demangle = true)
    {
        SPrint print;
        print.convert = convert;
        print.storage = storage;
        version (Demangler) {
            print.dynalloc = true;
        }
        print("  ");
        if (info.depth == TraceRecord.cInvalidDepth) {
            //termination record
            print(" (more)");
        } else {
            print("{,-3}  ", info.depth);
            Elf32_Sym* psym = sym_find_by_address(info.address);
            if (!psym) {
                print("0x{:x}\t [unknown]", info.address);
            } else {
                size_t offset = info.address - psym.st_value;
                print("0x{:x}-{}", info.address, offset);
                char* name = &gStrTab[psym.st_name];
                char[] aname = name[0..strlen(name)];
                version (Demangler) if (demangle) {
                    aname = demangler.demangle(aname);
                }
                print("\t {}", aname);
            }
        }
        return print.output;
    }

    alias ushort Elf32_Half;
    alias uint Elf32_Addr;
    alias uint Elf32_Off;
    alias int Elf32_Sword;
    alias int Elf32_Word;
    struct Elf32_Ehdr {
        align(1): //pointless align?
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

    char[] gStrTab;
    Elf32_Sym[] gSymTab;

    void readblock(FILE* file, int offset, void* ptr, size_t size) {
        if (!size)
            return;

        fseek(file, offset, SEEK_SET);
        if (fread(ptr, size, 1, file) != 1) {
            printf("Unable to read ELF file\n");
            abort();
        }
    }
    bool load_symbols(char* me) {
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
        //so... search backwards :-)
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

        gStrTab.length = strtab_section.sh_size;
        readblock(elf, strtab_section.sh_offset, gStrTab.ptr, gStrTab.length);

        gSymTab.length = symtab_section.sh_size / Elf32_Sym.sizeof;
        readblock(elf, symtab_section.sh_offset, gSymTab.ptr,
            Elf32_Sym.sizeof * gSymTab.length);

        return true;
    }

    Elf32_Sym* sym_find_by_address(Elf32_Addr addr) {
        for (int n = 0; n < gSymTab.length; n++) {
            Elf32_Sym* sym = &gSymTab[n];
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
        for (int n = 0; n < gSymTab.length; n++) {
            Elf32_Sym* sym = &gSymTab[n];
            if (!strcmp(&gStrTab[sym.st_name], name))
                return sym;
        }
        return null;
    }

    //borrowed from Phobos' internal/deh2.d
    //slightly modified (uint -> size_t, comments, abort())
    //license is a BSD something
    size_t my__eh_find_caller(size_t regbp, size_t *pretaddr) {
        size_t bp = *cast(size_t*)regbp;

        if (bp) {
            if (bp <= regbp)
                abort();
            *pretaddr = *cast(size_t*)(regbp + size_t.sizeof);
        }

        return bp;
    }

    //do a backtrace from this function on, starting with the caller function
    //this function allocates no memory; if prealloc is too small, it puts an
    // invalid marker entry as last entry (TraceRecord.cInvalidDepth)
    TraceRecord[] do_backtrace(TraceRecord[] prealloc) {
        size_t regebp;
        uint depth;

        if (!prealloc.length)
            return null;

        asm {
            mov regebp, EBP ;
        }

        for (;;) {
            uint retaddr;
            regebp = my__eh_find_caller(regebp, &retaddr);

            if (!regebp)
                break;

            if (depth == prealloc.length) {
                //stop backtrace here, put in invalid-marker
                prealloc[$-1].depth = TraceRecord.cInvalidDepth;
                break;
            }

            TraceRecord* cur = &prealloc[depth];
            cur.depth = depth;
            cur.ebp = regebp;
            cur.address = retaddr;

            depth++;

            if (sym_contains_address(stop_traceback_at, retaddr))
                break;
        }

        return prealloc[0..depth];
    }

    //trace on signal

    TraceRecord[cMaxBacktrace] gSignalTrace;

    extern(C) void signal_handler(int sig) {
        char[] signame;
        switch (sig) {
            case SIGSEGV: signame = "SIGSEGV"; break;
            case SIGFPE: signame = "SIGFPE"; break;
            default:
                signame = "unknown, add to mytrace.d/signal_handler()";
        }
        fprintf(stderr, "mytrace.d: Signal caught: %.*s\n", signame);
        auto info = do_backtrace(gSignalTrace);
        foreach (i; info) {
            char[cBacktraceLineBuffer] buffer = void;
            char[] l = printTraceRecord(buffer, i, false);
            fprintf(stderr, "%.*s", l);
        }
        abort();
    }

    void install_sighandlers() {
        version (SetSigHandler) {
            //add whatever signal barked on you
            signal(SIGSEGV, &signal_handler);
            signal(SIGFPE, &signal_handler);
        }
    }
}
