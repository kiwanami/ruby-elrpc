#!/usr/bin/ruby

require 'elrpc'

server = Elrpc.start_server()
server.wait
