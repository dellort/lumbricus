#!/usr/bin/env python

# this script takes a dmd dependency file, and outputs a graph in graphviz format
# also, detect cycles

# feel free to convert this to D, lol.

from optparse import OptionParser
import sys
import re

std_ignore = ["object", "tango.", "std.", "core."]

def print_help(option, opt, value, parser, do_exit=True):
    parser.print_help()
    print("")
    print("Generate the dependency file with:")
    print("    dmd -o- -deps=depfile rootfile.d")
    print("")
    print("Example to generate a graph with circular dependencies only:")
    print("    %s -c -C depfile graph.out" % parser.get_prog_name())
    print("")
    print("Render graph.out with:")
    print("    dot -T svg graph.out -o graph.svg")
    if do_exit: sys.exit(1)

parser = OptionParser(usage="%prog [options] depfile graph.out",
    description="Create a graphviz dependency graph from dmd module dependency file.",
    add_help_option=False)
parser.add_option("-h", "--help",
    action="callback", callback=print_help,
    help="show this help message and exit")
parser.add_option("-c", "--cycles-only",
    action="store_true", dest="cycles_only", default=False,
    help="show only nodes, that are parts of a cycle")
parser.add_option("-C", "--cycle-edges-only",
    action="store_true", dest="cycle_edges_only", default=False,
    help="show only edges, that are part of a cycle")
#parser.add_option("-t", "--remove-transitive-deps",
#    action="store_true", dest="remove_transitive_deps", default=False,
#    help="if A->B->C and A->C, don't add edge for A->C")
parser.add_option("-e", "--exclude",
    action="append", dest="ignore", default=[],
    help="ignore module (or if it ends with a '.', ignore all packages starting with this)")
parser.add_option("-i", "--include",
    action="append", dest="include", default=[],
    help="include only this module/package (similar to --exclude)")
parser.add_option("-p", "--package-mode",
    action="store_true", dest="package_mode", default=False,
    help="show dependencies between packages")
parser.add_option("--no-std-ignore",
    action="store_true", dest="no_std_ignore", default=False,
    help=("don't ignore standard modules (%s)" % std_ignore))
parser.add_option("--imports",
    action="append", dest="imports", default=[],
    help="include only modules which import this module (transitively)")
parser.add_option("--imports-depth",
    action="store", type="int", dest="import_depth", default=0,
    help="how many indirections max for --imports (0 means no restriction)")

# options contains all "dest" arg names as normal members
# args are all left non-option arguments as sequence
(options, args) = parser.parse_args()

if not options.no_std_ignore:
    options.ignore.extend(std_ignore)

if len(args) != 2:
    print_help(None, None, None, parser, False)
    print("")
    print("2 arguments expected (depfile, outfile), but received %s." % args)
    sys.exit(1)

# nodes[Node.name] = Node
nodes = {}

# one node per module (or package in package mode)
class Node:
    def __init__(self, name, id):
        self.name = name
        self.id = id
        # modules this module imports
        self.adj = []
        # number of cluster with cyclic dependencies
        # first cycle is 0, -1 means not part of a cycle
        self.cycle = -1

def compare_module_name(name, pattern):
    if name == pattern: return True
    if pattern.endswith(".") and name.startswith(pattern): return True
    return False

def is_ignored(name):
    for i in options.ignore:
        if compare_module_name(name, i): return True
    if len(options.include) > 0:
        for i in options.include:
            if not compare_module_name(name, i): return True
    return False

def getnode(name):
    if name not in nodes:
        nodes[name] = Node(name, len(nodes))
    return nodes[name]

# foo.moo.mod => foo.moo
# top-level files are considered to be in package "root"
def mod_to_package(mod):
    idx = mod.rfind(".")
    if idx < 0: idx = 0
    pkg = mod[:idx]
    if pkg == "": pkg = "root"
    return pkg

# append, but only if it isn't already in the array
def append_unique(seq, item):
    if item in seq: return
    seq.append(item)

deps = open(args[0])
# ignores some parts of the information
p = re.compile("([A-Za-z0-9._]+) \(.*\) : .* : ([A-Za-z0-9._]+) \(.*")
for line in deps:
    mod, imp = p.match(line).groups()
    if is_ignored(mod) or is_ignored(imp): continue
    if options.package_mode:
        mod = mod_to_package(mod)
        imp = mod_to_package(imp)
        if mod == imp:
            continue
    append_unique(getnode(mod).adj, getnode(imp))

# optional feature for looking at specific modules
if options.imports:
    marked = {}
    for i in options.imports:
        marked[getnode(i)] = True
    # this is like a reverse GC xD
    # mark all nodes which refer to at least one marked node
    depth = options.import_depth
    n = 0
    while depth == 0 or n < depth:
        n += 1
        nmark = {}
        for x in nodes.itervalues():
            if x not in marked:
                for a in x.adj:
                    if a in marked:
                        nmark[x] = True
        if len(nmark) == 0:
            break
        for x in nmark.iterkeys():
            marked[x] = True
    # remove all unmarked nodes
    nodes = {}
    for x in marked.iterkeys():
        nodes[x.name] = x
        x.adj = [i for i in x.adj if (i in marked)]

# tarjan algorithm to find cycles
# code borrowed from http://www.logarithmic.net/pfh/blog/01208083168
result = []
stack = []
low = {}

def visit(node):
    if node in low: return

    num = len(low)
    low[node] = num
    stack_pos = len(stack)
    stack.append(node)

    for successor in node.adj:
        visit(successor)
        low[node] = min(low[node], low[successor])

    if num == low[node]:
        component = tuple(stack[stack_pos:])
        del stack[stack_pos:]
        result.append(component)
        for item in component:
            low[item] = len(nodes)

for node in nodes.values():
    visit(node)
# end tarjan

cycles = 0
for e in result:
    if len(e) > 1:
        #s = ""
        for x in e:
            #s += x.name + " "
            x.cycle = cycles
        #print "> %s <" % s
        cycles = cycles + 1

# output graphviz graph

outf = open(args[1], "w")

outf.write('digraph "a" {\n')

for node in nodes.values():
    if options.cycles_only and not node.cycle >= 0: continue
    label = node.name
    if node.cycle >= 0:
        label = "%s [%s]" % (label, node.cycle)
    outf.write('  %s [label="%s"];\n' % (node.id, label))
    for to in node.adj:
        if options.cycles_only and not to.cycle >= 0: continue
        same_cycle = node.cycle >= 0 and node.cycle == to.cycle
        if options.cycle_edges_only and not same_cycle: continue
        outf.write('  %s -> %s [weight=%s %s]\n' % (node.id,
            to.id, 1 if same_cycle else 0, 'color=red' if same_cycle else ''))

outf.write('}\n')
