#!/usr/bin/ruby

require 'elrpc'

methods = [
   Elrpc::Method.new("method1", "args", "", &->(a) { 1 }),
   Elrpc::Method.new("test2", "a,b,c", "docstring here...", &->(a,b,c) { 2 }),
]

server = Elrpc.start_server(methods, 8888)
server.wait
