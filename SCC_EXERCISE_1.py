#!/usr/bin/python

"""
   This script written using Python 2.7 on CentOS7

   The script generates a graph and stores in a SQLLite3 database
   The table structure for the database is as follows:
     node   varchar(5),
     edges  varchar(50)
"""
import os
import sys
import time
import resource
import sqlite3

graph={}
#max_node_num=100000000
max_node_num=99
alpha_list=['a','b','c','d','e','f', 'g','h','i','j','k','l','m',
            'n','o','p','q','r','s','t','u','v','w','x','y','z']

def generate_random_vertices(num_vertices, alpha_node):
  import random     # import of random local to function
  global max_node_num
  global alpha_list
  Graph={}

  index=1
  while index <= num_vertices:   # loop on no. of vertices
     # generate a new random number in the range 1..num_vertices
     if (alpha_node in ('Y','y')):
        rand_vertex=random.randrange(0, (max_node_num), 1)
        vertex="%s" %alpha_list[rand_vertex]
     else:
        rand_vertex=random.randrange(1, (max_node_num+1), 1)
        vertex="%s" %rand_vertex
     while (vertex in Graph):  # if the vertex in list
        # generate a new random number for the vertex
        if (alpha_node in ('Y','y')):
           rand_vertex=random.randrange(0, (max_node_num), 1)
           vertex="%s" %alpha_list[rand_vertex]
        else:
           rand_vertex = random.randrange(1, (max_node_num+1), 1)
           vertex="%s" %rand_vertex
  
     # add the vertex to the list
     if vertex not in Graph:
        Graph[vertex] = []

     index += 1
  # end for-loop
  
  return(Graph)
# end function


def generate_random_edges(Graph, num_edges, alpha_node):
  """
  this function generated a random edge vertex for each node
  from the Nodes list.  I will try to put num_edges per node.
  The edge list is stored as tuples of two values (vert, edge_vert)
  At the end of the function, it is passed back
  """
  import random
  Nodes=Graph.keys()
  edge_index=0
  no_edge=[]

  # loop for the vertices of the graph
  for node in Nodes:
    # calculate number of edges to produce for current node
    # starting at 0 in the randrange because you can also have
    # 0 edges for a node
    rand_edges=random.randrange(0, num_edges-1, 1)
    while rand_edges > num_edges:
       # if we get a rand_edges > num_edges
       rand_edges=random.randrange(0, num_edges-1, 1)
       
    if rand_edges == 0:
       # store the current node so no other nodes may connect to it
       no_edge.append(node)
       continue    # go to next vertex

    # loop rand_edges times
    index=1
    while index <= rand_edges:
        stuck=0
        edge_index=random.randrange(0, len(Nodes), 1)

        # check if the node at index in list for no_edges
        while (Nodes[edge_index] in no_edge):
           edge_index=random.randrange(0, len(Nodes), 1)
        # end while check for node in no_edge list

        while (Nodes[edge_index] in Graph[node]):
          # swap the node and vertex and check if it is present
          if (node not in Graph[Nodes[edge_index]]):
             Graph[Nodes[edge_index]].append(node)
          else:
             edge_index=random.randrange(0, len(Nodes), 1)
             stuck+=1
             if (stuck == 5): break
        # end while check

        # when a connection is made from a node to an edge vertex
        # also make a connection from the edge vertex back to the
        # origin node.  Store the pair as a tuple
        if (Nodes[edge_index] not in Graph[node]):
           Graph[node].append(Nodes[edge_index])
           if (node not in Graph[Nodes[edge_index]]):
              Graph[Nodes[edge_index]].append(node)

        index+=1
    # end inner loop
  return(Graph)
# end function


def parse_args(script_name, arg_list):
   import getopt
   import random

   global max_node_num
   max_vertices=10000
   edge_factor=0.25
   alpha_nodes='N'
   num_vertices = random.randrange(5, max_vertices, 1)
   num_edges = random.randrange(4, int(max_vertices*edge_factor), 1)

   try:
      opts, args = getopt.getopt(arg_list,"ahn:e:",["alpha=","nodes=","edges="])
   except getopt.GetoptError:
      print '%s [-a] -n <#_of_nodes> -e <#_of_edges>' %script_name
      print ' '*15 + "OR"
      print '%s --alpha=Y --nodes=<#_of_nodes> --edges=<#_of_edges>' %script_name
      sys.exit(2)
   for opt, arg in opts:
      if opt == '-h':
         print '%s -a -n <#_of_nodes> -e <#_of_edges>' %script_name
         print ' '*15 + "OR"
         print '%s --alpha=Y --nodes=<#_of_nodes> --edges=<#_of_edges>' %script_name
         sys.exit()
      elif opt in ("-a", "--alpha"):
         alpha_nodes='Y'
         num_vertices = 6
         num_edges = 4
      elif opt in ("-n", "--nodes"):
         num_vertices = int(arg)
      elif opt in ("-e", "--edges"):
         num_edges = int(arg)

   if num_edges > num_vertices:
      num_edges = num_vertices-1

   if num_vertices > max_vertices:
      num_vertices = max_vertices-1

   if (num_edges > num_vertices):
      num_edges = int(num_vertices * edge_factor)

   if (num_vertices < 30):
      if alpha_nodes in ('Y','y'):
         max_node_num = 26
      else:
         max_node_num = 29

   elif (num_vertices > 30 and num_vertices < 101):
      max_node_num = 99
   elif (num_vertices > 100 and num_vertices < 1001):
      max_node_num = 999
   elif (num_vertices > 1000 and num_vertices < 10001):
      max_node_num = 9999
   return(num_vertices, num_edges, alpha_nodes)
# end function


def get_memusage():

  usage=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1000
  return(usage)
# end function


# --------- MAIN STARTS HERE  -----------------------
script_name=sys.argv[0]

(num_vertex,num_edges,alphanodes)=parse_args(script_name, sys.argv[1:])

print "Mem usage at start: ", get_memusage(), " MB"
print ""
print "Preparing Graph of %s Nodes" %num_vertex
print ""
# generates random node values for num_vertices and returns the list
start=time.clock()
Graph=generate_random_vertices(num_vertex, alphanodes)
fin=time.clock()
print ""
print "Random Node Graph generated in: %s sec " %(fin-start)
print "    Mem usage after Graph init: ", get_memusage(), " MB"

print ""
print "Preparing random edges (%s) for nodes in graph ..." %num_edges
# generates the random edge for the nodes in the Node list. return list
# is a list of tuples which is used for populating into the DB table
start=time.clock()
Graph=generate_random_edges(Graph,  num_edges, alphanodes)
fin=time.clock()
print ""
print "Random Edges in Graph generated in: %s sec " %(fin-start)
print "        Mem usage after Graph init: ", get_memusage(), " MB"


# set connection to the file database
print ""
print "Connecting to SQLite3 DB"
connection = sqlite3.connect("graph.db")

cursor=connection.cursor()

sql_command="select count(*) from graph_info;"
try:
   cursor.execute(sql_command)
   count=cursor.fetchone()[0]
   if count > 0:
      # truncate old info in the table
      try:
         print "     Deleting old records from database"
         trunc_cmd="delete from graph_info;"
         cursor.execute(trunc_cmd)
         connection.commit()
      except:
         pass
except:
   # table doesn't exist -- create it
   print "    Creating database table: graph_info"
   create_cmd="""
       CREATE TABLE graph_info(
           node     varchar(20),
           edges    varchar(20));
              """
   cursor.execute(create_cmd)
   connection.commit()

# store nodes and edges to the table
print "     Writing Graph to database"
for vertex in Graph:
  
  # if vertex has no edges, 
  if len(Graph[vertex])==0:
    insert_cmd="""
          INSERT INTO graph_info(node, edges)
                         VALUES ('%s', 'EMPTY');
             """ %(vertex)
    cursor.execute(insert_cmd)
    continue
     
  # write the edges of the current vertex   
  for edge in Graph[vertex]:
    # store one vertex and edge_to_vertex
    insert_cmd="""
          INSERT INTO graph_info(node, edges)
                         VALUES ('%s', '%s');
             """ %(vertex, edge)
    cursor.execute(insert_cmd)
# end loop

print "     Commiting data insert"
connection.commit()
print "Closing database connection"
connection.close()
