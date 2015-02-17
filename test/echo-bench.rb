#!/usr/bin/ruby

require 'elrpc'
require 'benchmark'
require 'monitor'

cl = Elrpc.start_process(["ruby","#{__dir__}/_echo.rb"])

rnd = Random.new 1000
array = (1..100).map {|i| rnd.rand*10000 }
hash  = array.inject({}) {|h, i| h[i] = rnd.rand*10000; h }
str   = array.join("")

n = 2000
Benchmark.bm(10) do |x|
  tint = x.report("int")    { n.times { cl.call_method("echo", 1) } }
  tinta = x.report("int_a") do
    wait_lock = Mutex.new
    wait_cv = ConditionVariable.new
    count = 0
    n.times do
      cl.call_method_async("echo", 1) do |val|
        count += 1
        wait_lock.synchronize do
          wait_cv.signal if count == n
        end
      end
    end
    wait_lock.synchronize do
      wait_cv.wait(wait_lock)
    end
  end
  tstr = x.report("string") { n.times { cl.call_method("echo", str) } }
  tarr = x.report("array")  { n.times { cl.call_method("echo", array) } }
  thsh = x.report("hash")   { n.times { cl.call_method("echo", hash) } }
  puts sprintf("(call/sec) int: %.1f  int_async: %.1f  string: %.1f  array: %.1f  hash: %.1f", 
               n/tint.total, n/tinta.total, n/tstr.total, n/tarr.total, n/thsh.total)
end

cl.stop
