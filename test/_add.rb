#!/usr/bin/ruby

require 'elrpc'

server = Elrpc.start_server([],8888)
server.def_method "add" do |a,b|
  a+b
end
server.wait
