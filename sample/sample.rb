#!/usr/bin/ruby

require 'elrpc'

# start server
server = Elrpc.start_server()

server.def_method "echo" do |*arg|
  arg
end

server.def_method "add" do |a,b|
  a+b
end

server.def_method "inject","init, op, list","Enumerable#inject" do |init, op, list|
  list.inject(init, op)
end

# sleep the main thread and wait for closing connection
server.wait 
