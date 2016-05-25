#!/usr/bin/python

"""
   This script written using Python 2.7 on CentOS7

   The script reads a graph stored in a SQLLite3 database
   The detail is read into the graph dictionary
   Then the function for scc is called on the graph with
   a reversed list of nodes.  Actual scc function received
   a graph (dict), a reversed graph (dict), and nodes.
"""
import os
import re
import ast
import sys
import time
import sqlite3
import resource
from itertools import groupby
from collections import defaultdict

#set rescursion limit and stack size limit
sys.setrecursionlimit(10 ** 6)
resource.setrlimit(resource.RLIMIT_STACK, (2 ** 29, 2 ** 30))

"""
  The class for Track, and functions for dfs, dfs_loop, and
  scc obtained on the web at site: 
  https://teacode.wordpress.com/2013/07/27/algo-week-4-graph-search-and-kosaraju-ssc-finder/
  Author of the functions: Chuntao Lu
  Documenting that I am giving credit to him
"""
# define tracking class
class Track(object):
    """Keeps track of the current time, current source, component leader,
    finish time of each node and the explored nodes."""
 
    def __init__(self):
        self.current_time = 0
        self.current_source = None
        self.leader = {}
        self.finish_time = {}
        self.explored = set()
 
def dfs(graph_dict, node, track):
    """Inner loop explores all nodes in a SCC. Graph represented as a dict,
    {tail node: [head nodes]}. Depth first search runs recrusively and keeps
    track of the parameters"""
 
    track.explored.add(node)
    track.leader[node] = track.current_source
    for head in graph_dict[node]:
        if head not in track.explored:
            dfs(graph_dict, head, track)
    track.current_time += 1
    track.finish_time[node] = track.current_time
 
 
def dfs_loop(graph_dict, nodes, track):
    """Outter loop checks out all SCCs. Current source node changes when one
    SCC inner loop finishes."""
 
    for node in nodes:
        if node not in track.explored:
            track.current_source = node
            dfs(graph_dict, node, track)
 
 
def scc(graph, reverse_nodes):
    """First runs dfs_loop on reversed graph with nodes in decreasing order,
    then runs dfs_loop on orignial graph with nodes in decreasing finish
    time order(obatined from firt run). Return a dict of {leader: SCC}."""
 
    out = defaultdict(list)
    track = Track()
    dfs_loop(graph, reverse_nodes, track)
    sorted_nodes = sorted(track.finish_time,
                          key=track.finish_time.get, reverse=True)
    track.current_time = 0
    track.current_source = None
    track.explored = set()
    dfs_loop(graph, sorted_nodes, track)
    for lead, vertex in groupby(sorted(track.leader, key=track.leader.get),
                                key=track.leader.get):
        out[lead] = list(vertex)
    return out

# --------- MAIN STARTS HERE  -----------------------
# set connection to the file database
connection = sqlite3.connect("graph.db")
Edge_List=[]

cursor=connection.cursor()

sql_command="select node, edges from graph_info;"
try:
   cursor.execute(sql_command)
   Edge_List=cursor.fetchall()
except:
   print "Unable to read from database"
   sys.exit(-2)
connection.close()
graph={}
rev_Node_List=[]

# fills the graph dict
for edge_info in Edge_List:
    (vertex, edge)=edge_info
    try:
       vertex=int(vertex)
    except ValueError:
       pass

    if edge not in ('EMPTY',''):
       try:
          edge=int(edge)
       except ValueError:
          pass

    if (vertex in graph):
       # if there were no edges for the vertex
       if (edge in ('', 'EMPTY')):
          graph[vertex]=[]
          continue   # do not include vertex without edges
       else:
          graph[vertex].append(edge)
    else:
       # if there were no edges for the vertex
       if (edge in ('', 'EMPTY')):
          graph[vertex]=[]
          continue   # do not include vertex without edges
       else:
          graph[vertex]=[edge]

    rev_Node_List.append(vertex)
# end loop

temp=set(rev_Node_List)
rev_Node_List=list(temp)
rev_Node_List.reverse()

OUT=scc(graph, rev_Node_List)
SCC=dict(OUT)  # cast defaultdict collection to standard dict

print ""
print "STATISTICS:"
print "GRAPH INPUT"
print "Number of nodes/vertices in input graph: ",len(graph)
for node in graph:
    temp=[]
    for edge in graph[node]:
      temp.append("%s"%edge)
    edges=",".join(temp)
    print "    %s: [%s]" %(node, edges)

print ""
print "Number of SCC(s) [Strongly Connected Components]: ",len(SCC)
print "SCC Vertices: ",
for keys in SCC.keys():
    print "%c "%keys,
print ""
print "Number of Nodes for each SCC(s):"
for scc_node in SCC:
    print "   Lead %s: %s" %(scc_node,len(SCC[scc_node]))
    print "            ",
    for scc_edge in SCC[scc_node]:
        print scc_edge,
    print ""
