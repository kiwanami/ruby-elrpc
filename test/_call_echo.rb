#!/usr/bin/ruby

require 'elrpc'

cl = Elrpc.start_client(8888)
ret = cl.call_method("echo", 1)
puts ret
cl.stop


