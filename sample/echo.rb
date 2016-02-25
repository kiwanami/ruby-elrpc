#!/usr/bin/ruby

require 'elrpc'

Elrpc.set_default_log_level(Logger::DEBUG)

# start server
server = Elrpc.start_server()

# define a method
server.def_method "echo" do |arg|
  # just return the given argument value
  puts arg
  arg
end

# sleep the main thread and wait for closing connection
server.wait 
