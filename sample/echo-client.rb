#!/usr/bin/ruby

require 'elrpc'

# start a child process
cl = Elrpc.start_process(["ruby","echo.rb"])

# synchronous calling
puts cl.call_method("echo", "1 hello")

# asynchronous calling
cl.call_method_async("echo", "3 world") do |err, value|
  puts value
end

puts "2 wait"
sleep 0.2

puts "4 ok"

# kill the child process
cl.stop
