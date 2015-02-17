#!/usr/bin/ruby

require 'elrpc'

server = Elrpc.start_server([], 8888)
server.def_method "echo" do |*arg|
  arg
end
server.wait
