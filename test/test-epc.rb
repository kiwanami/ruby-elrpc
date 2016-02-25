#!/usr/bin/ruby

require 'test/unit'
require 'timeout'
require 'elrpc'

def base(file)
  "#{__dir__}/#{file}"
end

STDOUT.sync = true

class TestEPC < Test::Unit::TestCase
  
  sub_test_case "01 Process" do
    test "Start with port num and Getting it" do
      port = nil
      IO.popen(["ruby", base("_echo.rb")]) do |io|
        port = io.readline.strip
        Process.kill("TERM",io.pid)
      end
      assert_equal("8888", port)
    end

    test "Start without port num and getting the port num" do
      port = nil
      IO.popen(["ruby", base("_process.rb")]) do |io|
        port = io.readline
        Process.kill("TERM",io.pid)
      end
      assert_true(port.to_i > 0)
    end

    test "Start server process" do
      sv = nil
      begin
        timeout(5) do
          sv = Elrpc.start_process(["ruby",base("_echo.rb")], 8888)
          sv.stop
          assert_true(true)
        end
      rescue  => e
        puts e,e.backtrace
        assert_true(false)
        sv.stop_force if sv
      end
    end
  end



  def with_epc(progname)
    IO.popen(["ruby", base(progname)]) do |io|
      port = io.readline.to_i
      thread = Thread.start { loop { puts io.readline } }
      client = Elrpc.start_client(port)
      client.logger.level = Logger::ERROR
      begin
        yield client
      rescue => e
        Process.kill("TERM",io.pid)
        raise e
      ensure
        client.stop
        thread.kill
      end
    end
  end


  sub_test_case "02 Echo" do

    test "Echo sync" do
      with_epc "_echo.rb" do |client|
        ret = client.call_method("echo", "hello")
        assert_equal "hello", ret[0]
        ret = client.call_method("echo", 12345)
        assert_equal 12345, ret[0]
      end
    end

    test "Echo async" do
      with_epc "_echo.rb" do |client|
        client.call_method_async("echo", "hello") do |err, ret|
          assert_equal "hello", ret[0]
        end
        client.call_method_async("echo", -12.345) do |err, ret|
          assert_equal -12.345, ret[0]
          client.stop
        end
        client.wait
      end
    end
  end


  sub_test_case "03 Add" do
    
    test "Add sync" do 
      with_epc "_add.rb" do |client|
        ret = client.call_method("add", 1, 2)
        assert_equal 3, ret
        ret = client.call_method("add", "A", "B")
        assert_equal "AB", ret
      end
    end
    
    test "Add async" do
      with_epc "_add.rb" do |client|
        client.call_method_async("add", 3, 4) do |err, ret|
          assert_equal 7, ret
        end
        client.call_method_async("add", "C","D") do |err, ret|
          assert_equal "CD", ret
          client.stop
        end
        client.wait
      end
    end
  end

  sub_test_case "04 Errors" do

    test "Error sync" do
      with_epc "_errors.rb" do |client|
        assert_raise_message /divided by 0/ do
          ret = client.call_method("num_error")
        end
        assert_raise_message /Raise!/ do
          ret = client.call_method("raise_error")
        end
        ret = client.call_method("echo", "recover!!")
        assert_equal "recover!!", ret[0]
      end
    end

    test "Error async" do
      with_epc "_errors.rb" do |client|
        client.call_method_async("num_error") do |err, ret|
          assert_equal "divided by 0", err.remote_message
        end
        client.call_method_async("raise_error") do |err, ret|
          assert_equal "Raise!", err.remote_message
          client.stop
        end
        client.wait
      end
    end

    test "EPC Error" do
      with_epc "_echo.rb" do |client|
        assert_raise_kind_of Elrpc::EPCStackError do
          client.call_method("echo", Elparser::Parser.new )
        end
        assert_raise_kind_of Elrpc::EPCStackError do
          client.call_method("echo??", 1 )
        end
        ret = client.call_method("echo", "recover!!")
        assert_equal "recover!!", ret[0]
      end
    end

  end

  sub_test_case "05 Query" do
    test "Query sync" do
      with_epc "_methods.rb" do |client|
        ret = client.query_methods
        assert_equal 2, ret.size
        assert_equal :method1, ret[0][0]
        assert_equal "args", ret[0][1]
        assert_equal "", ret[0][2]
        assert_equal :test2, ret[1][0]
        assert_equal "a,b,c", ret[1][1]
        assert_equal "docstring here...", ret[1][2]
      end
    end
  end
  
end
