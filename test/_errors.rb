#!/usr/bin/ruby

require 'elrpc'

server = Elrpc.start_server([],8888)
server.def_method "num_error" do |arg|
  1/0
end
server.def_method "raise_error" do |arg|
  raise "Raise!"
end
server.def_method "echo" do |*arg|
  arg
end
server.wait
