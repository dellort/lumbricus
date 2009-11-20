#!/usr/bin/env python

# this script takes a dmd dependency file, and outputs a graph in graphviz format
# also, detect circles

# feel free to convert this to D, lol.


# show only nodes, that are parts of a cycle
cycles_only = True
# only edges that are part of a cycle
cycle_edge_only = True
# each entry is a module name or, if it ends with '.', a package prefix
ignore = ["tango.", "object"]


import sys
import re

if len(sys.argv) != 2:
    print "dmd dependency file as argument expected"
    print "generate the dependency file with: dmd -o- rootfile.d -deps=depfile"
    sys.exit(1)

nodes = {}

class Node:
    def __init__(self, name, id):
        self.name = name
        self.id = id
        self.adj = []
        # number of cluster with cyclic dependencies
        # first cycle is 0, -1 means not part of a cycle
        self.cycle = -1

def is_ignored(name):
    for i in ignore:
        if i == name: return True
        if i.endswith(".") and name.startswith(i): return True
    return False

def getnode(name):
    if not nodes.has_key(name):
        nodes[name] = Node(name, len(nodes))
    return nodes[name]

deps = open(sys.argv[1])
# ignores some parts of the information
p = re.compile("([A-Za-z0-9._]+) \(.*\) : .* : ([A-Za-z0-9._]+) \(.*")
for line in deps:
    mod, imp = p.match(line).groups()
    if is_ignored(mod) or is_ignored(imp): continue
    getnode(mod).adj.append(getnode(imp))

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

print 'digraph "a" {'

for node in nodes.values():
    if cycles_only and not node.cycle >= 0: continue
    label = node.name
    if node.cycle >= 0:
        label = "%s [%s]" % (label, node.cycle)
    print '%s [label="%s"];' % (node.id, label)
    for to in node.adj:
        if cycles_only and not to.cycle >= 0: continue
        same_cycle = node.cycle >= 0 and node.cycle == to.cycle
        if cycle_edge_only and not same_cycle: continue
        print '%s -> %s [weight=%s %s]' % (node.id, to.id, 1 if same_cycle else 0, 'color=red' if same_cycle else '')

print "}"
