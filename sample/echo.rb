#!/usr/bin/ruby

require 'elrpc'

# start server
server = Elrpc.start_server()

# define a method
server.def_method "echo" do |arg|
  # just return the given argument value
  arg
end

# sleep the main thread and wait for closing connection
server.wait 
