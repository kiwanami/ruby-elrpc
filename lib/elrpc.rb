# -*- coding: utf-8 -*-
require "elrpc/version"

require "socket"
require "thread"
require "monitor"
require "logger"
require "timeout"

require "elparser"


module Elrpc

  @@default_log_level = Logger::WARN

  # Logger::WARN, Logger::INFO, Logger::DEBUG
  def self.set_default_log_level(level)
    @@default_log_level = level
  end

  def self.default_log_level
    @@default_log_level
  end

  @@count = 1

  def self.gen_uid
    @@count += 1
    @@count
  end

  def self.get_logger_format(comid)
	return "%Y/%m/%d %H:%M:%S #{comid}"
  end



  def self.start_server(methods = [], port = 0)
    server_socket = TCPServer.open(port)
    port_number = server_socket.local_address.ip_port
    STDOUT.puts "#{port_number}"
    STDOUT.flush
    socket = server_socket.accept
    server = RPCService.new("SV", socket, methods)
    server.add_close_hook do
      server_socket.close
    end
    return server
  end

  def self.start_client(port, methods=[], host = "127.0.0.1")
    socket = TCPSocket.open(host, port)
    client = RPCService.new("CL", socket, methods)
    return client
  end

  def self.start_process(cmd, port = nil)
    svr = Service.new(cmd, port)
    svr.start
    return svr
  end

  class Service

    attr_reader :cmd, :port, :client
    attr :output

    # cmd = ["ruby", "_call.rb"]
    def initialize(cmd, port)
      @cmd = cmd
      @port = port
    end

    def _start_logger
      return Thread.start do
        loop do
          ret = @io.readline
          break if ret.nil?
          @logger.puts(ret) if @logger
        end
      end
    end

    def start
      @io = IO.popen(@cmd)
      if port.nil?
        @port = @io.readline.to_i
      end
      @output = nil
      @thread = _start_logger
      # wait for port
      timeout(4) do
        loop do
          begin
            socket = TCPSocket.open("127.0.0.1", @port)
            socket.close
            #puts("Peer port is OK.")
            break
          rescue => e
            #puts("Peer port is not opened. Try next time...")
            sleep(0.2)
          end
        end
      end
      @client = Elrpc.start_client(@port)
      return self
    end
    
    def register_method(method)
      @client.register_method(method)
    end

    def def_method(name, argdoc=nil, docstring=nil, &block)
      @client.def_method(name, argdoc, docstring, &block)
    end

    def call_method_async(name, *args, &block)
      @client.call_method_async(name, *args, &block)
    end

    def call_method(name, *args)
      @client.call_method(name, *args)
    end

    def query_methods_async(&block)
      @client.query_methods(&block)
    end

    def query_methods
      @client.query_methods
    end

    def stop
      @client.stop
    end
    
  end


  
  class Method

    attr_reader :name, :proc
    attr :argdoc, :docstring

    def initialize(name, argdoc=nil, docstring=nil, &proc)
      @name = name.to_sym
      @proc = proc
      @argdoc = argdoc
      @docstring = docstring
    end
    
    def call(args)
      @proc.call(*args)
    end

  end

  class EPCRuntimeError < StandardError
    def initialize(_classname, _message, _backtrace)
      @_classname = _classname
      @_message = _message
      @_backtrace = _backtrace
    end

    def message
      "#{@_classname} : #{@_message}"
    end
    def to_s
      message
    end

    def remote_classname
      @_classname
    end
    def remote_message
      @_message
    end
    def remote_backtrace
      @_backtrace
    end

  end

  class EPCStackError < StandardError
    def initialize(_classname, _message, _backtrace)
      @_classname = _classname
      @_message = _message
      @_backtrace = _backtrace
    end

    def message
      "#{@_classname} : #{@_message}"
    end
    def to_s
      message
    end

    def remote_classname
      @_classname
    end
    def remote_message
      @_message
    end
    def remote_backtrace
      @_backtrace
    end
  end


  ## 送信用データクラス
  ## キューに入れるために使う

  class CallMessage
    attr_reader :uid, :method, :args, :block

    def initialize(uid, method, args, block)
      @uid = uid
      @method = method
      @args = args
      @block = block
    end

    def to_ast
      [:call, @uid, @method, @args]
    end
  end

  class MethodsMessage
    attr_reader :uid, :block

    def initialize(uid, block)
      @uid = uid
      @block = block
    end

    def to_ast
      [:methods, @uid]
    end
  end

  class ReturnMessage
    attr_reader :uid, :value

    def initialize(uid, value)
      @uid = uid
      @value = value
    end

    def to_ast
      [:return, @uid, @value]
    end
  end

  class ErrorMessage
    attr_reader :uid, :error_msg

    def initialize(uid, error_msg)
      @uid = uid
      @error_msg = error_msg
    end

    def to_ast
      [:'return-error', @uid, @error_msg]
    end
  end

  class EPCErrorMessage
    attr_reader :uid, :error_msg

    def initialize(uid, error_msg)
      @uid = uid
      @error_msg = error_msg
    end

    def to_ast
      [:'epc-error', @uid, @error_msg]
    end
  end


  class RPCService

	attr_reader :socket_state
	attr_accessor :logger
    
    def initialize(name, socket, methods = nil)
	  @logger = Logger.new(STDOUT)
	  @logger.level = Elrpc::default_log_level
      @logger.datetime_format = Elrpc.get_logger_format(name)

      @methods = Hash.new # name -> Method
      @session = Hash.new # uid -> proc
      @session_lock = Monitor.new

	  @sending_queue = Queue.new # CallMessage

      @socket = socket
      @socket_state_lock = Monitor.new
	  @socket_state = :socket_opened

      @wait_lock = nil
      @wait_cv = nil
      @close_hooks = []

      if methods then
        methods.each do |m|
          register_method(m)
        end
      end

      @sender_thread = Thread.start { sender_loop }
      @receiver_thread = Thread.start { receiver_loop }
      @worker_pool = WorkerPool.new(1, @logger)

      @logger.debug ":ready for I/O stream."
    end

    # 自分にメソッドを登録する
    def register_method(method)
      @methods[method.name] = method
    end

    # register_method の簡易版
    def def_method(name, argdoc=nil, docstring=nil, &block)
      register_method(Method.new(name, argdoc, docstring, &block))
    end

    # 相手のメソッドを呼ぶ
    # block(err, value)
    def call_method_async(name, *args, &block)
      uid = Elrpc.gen_uid
      msg = CallMessage.new(uid, name, args, block)
      # ここは競合しないのでロックしない
      @session[uid] = msg
      @sending_queue.push(msg)
      uid
    end

    # 相手のメソッドを呼ぶ（同期版）
    def call_method(name, *args)
      mutex = Mutex.new
      cv = ConditionVariable.new
      ret = nil
      ex = nil
      call_method_async(name, *args) do |err, value|
        mutex.synchronize do
          ex = err
          ret = value
          cv.signal
        end
      end
      mutex.synchronize do
        cv.wait(mutex)
      end
      if !ex.nil?
        raise ex
      end
      return ret
    end

    # 接続相手のメソッド一覧を返す
    # [[name, argdoc, docstring], ...]
    def query_methods_async(&block)
      uid = Elrpc.gen_uid
      msg = MethodsMessage.new(uid, block)
      @session[uid] = msg
      @sending_queue.push(msg)
      uid
    end

    # 接続相手のメソッド一覧を返す（同期版）
    # [[name, argdoc, docstring], ...]
    def query_methods
      mutex = Mutex.new
      cv = ConditionVariable.new
      ret = nil
      ex = nil
      query_methods_async do |err, value|
        mutex.synchronize do
          ex = err
          ret = value
          cv.signal
        end
      end
      mutex.synchronize do
        cv.wait(mutex)
      end
      if !ex.nil?
        raise ex
      end
      return ret
    end

    def stop
      if @socket_state == :socket_opened then
        @logger.debug "RPCService.stop: received!"
        @worker_pool.kill
        @socket_state = :socket_closing
        @socket.close
        @sending_queue << nil # stop message
        @sender_thread.join(4) unless Thread.current == @sender_thread
        @receiver_thread.join(4) unless Thread.current == @receiver_thread
        _clear_waiting_sessions
        @socket_state = :scoket_not_connected
      end
      _wakeup
      @logger.debug "RPCService.stop: completed"
    end

    # ソケットが相手から切断されるまでメインスレッドを止める
    def wait
      @wait_lock = Mutex.new
      @wait_cv = ConditionVariable.new
      @wait_lock.synchronize do
        @wait_cv.wait(@wait_lock)
      end
      stop
    end

    def add_close_hook(&block)
      @close_hooks << block
    end


    private

    # RPC呼び出しで待ってるスレッドを全てエラーにして終了させる
    def _clear_waiting_sessions
      @session_lock.synchronize do
        @session.keys.each do |uid|
          _session_return(uid, "EPC Connection closed", nil)
        end
      end
    end

    def _socket_state_lock
      @socket_state_lock.synchronize do
        yield
      end
    end

    # もし、メインスレッドが停止していれば再開させて終了させる
    def _wakeup
      if @wait_lock
        @wait_lock.synchronize do
          @wait_cv.signal
        end
      end
    end

    # 相手にシリアライズされたデータを送る
    def _send_message(msg)
      msg = msg.encode("UTF-8") + "\n"
      len = msg.bytesize
      body = sprintf("%06x%s",len,msg)
      @socket.write(body)
      @socket.flush
    end

    # 呼び出し元に値を返して、セッションをクリアする
    def _session_return(uid, error, value)
      m = nil
      @session_lock.synchronize do
        m = @session[uid]
        @session.delete(uid)
      end
      if m then
        m.block.call(error, value)
      end
    end

    def sender_loop
	  loop do
		begin
          entry = @sending_queue.shift
          if entry.nil? then
            @logger.debug "Queue.shift received stop message."
            break
          end
          @logger.debug "Queue.shift [#{@sending_queue.size}] : #{entry.uid}"
          body = Elparser.encode( entry.to_ast )
          @logger.debug "Encode : #{body}"
          _send_message( body )
          @logger.debug "  Queue -> sent #{entry.uid}"
		rescue Elparser::EncodingError => evar
		  @logger.warn "[sendloop] #{evar.to_s}  "
          err = EPCStackError.new(evar.class.name, evar.message, evar.backtrace)
		  _session_return(entry.uid, err, nil) if entry
		rescue => evar
		  mes = evar.message
		  @logger.warn "[sendloop] #{evar.to_s}  "
		  if mes["abort"] then
			@logger.warn "  [sendloop] disconnected by the peer."
            @socket_state = :socket_not_connected
		  elsif evar.class == IOError then
			@logger.warn evar.backtrace.join("\n")
            @socket_state = :socket_closing
		  end
		  _session_return(entry.uid, evar, nil) if entry
		end # begin
        if @socket_state == :socket_closing || 
            @socket_state == :socket_not_connected then
          @logger.debug "[sender-thread] terminating..."
          break
        end
	  end # loop
      @logger.debug "[sender-thread] loop exit : #{@socket_state}"
      _wakeup
      @logger.debug "[sender-thread] exit--------------"
    end

    def receiver_loop
      parser = Elparser::Parser.new
	  loop do
        ast = nil # for error message and recovery
        uid = nil
		begin
		  lenstr = @socket.read(6)
          if lenstr.nil? then
            @logger.debug "[rcvloop] Socket closed!"
            break
          end
          len = lenstr.to_i(16)
		  @logger.debug "Receiving a message : len=#{len}"
          body = @socket.read(len) # 1 means LF
          if body.nil? then
            @logger.debug "[rcvloop] Socket closed!"
            break
          end
          body.force_encoding("utf-8")
          @logger.debug "Parse : #{body}/#{body.encoding}"
          ast = parser.parse(body)
          raise "Unexpected multiple s-expression : #{body}" if ast.size != 1
          ast = ast[0].to_ruby
          uid = ast[1]
		  case ast[0]
		  when :call
			@logger.debug "  received: CALL : #{uid}"
            _call(ast)
		  when :return
			@logger.debug "  received: RETURN: #{uid}"
            _return(ast)
		  when :'return-error'
			@logger.debug "  received: ERROR: #{uid}"
            _return_error(ast)
		  when :'epc-error'
			@logger.debug "  received: EPC_ERROR: #{uid}"
            _epc_error(ast)
		  when :'methods'
			@logger.debug "  received: METHODS: #{uid}"
            _query_methods(ast)
		  else
			@logger.debug "  Unknown message code. try to reset the connection. >> #{body}"
            @socket_state = :socket_closing
            @sending_queue.push nil # wakeup sender thread
			return
		  end # case
          if @socket_state == :socket_closing then
            @logger.debug "[receiver-thread] terminating..."
            break
          end
		rescue Exception => evar
          @logger.debug "[rcvloop] Exception! #{evar}"
		  mes = evar.message
		  if uid && @session[uid] then
            _session_return(uid, evar, nil)
		  end
		  if mes["close"] || mes["reset"] then
			@logger.debug "  [rcvloop] disconnected by the peer."
			break
		  elsif evar.kind_of?(IOError) then
			@logger.debug "  [rcvloop] IOError."
            @socket_state = :socket_closing
			break
		  else
			@logger.warn "  [rcvloop] going to recover the communication."
			bt = evar.backtrace.join("\n")
			@logger.warn "  [rcvloop] #{bt}"
		  end
		end # begin rescue
        ast = nil
        uid = nil
	  end # loop
      @logger.debug "[receiver-thread] loop exit : #{@socket_state}"
      _wakeup
      @logger.debug "[receiver-thread exit]--------------"
    end

    # 相手からメソッドを呼ばれた
    def _call(ast)
      _, uid, name, args = ast
      @logger.debug ": called: Enter: #{name} : #{uid}"
      method = @methods[name.to_sym]
      if method then
        task = -> do
          msg = nil
          begin
            ret = method.call(args)
            msg = ReturnMessage.new(uid, ret)
          rescue => e
            @logger.debug ": called: Error!: #{name} : #{uid} : #{e}"
            @logger.debug e
            msg = ErrorMessage.new(uid, [e.class.name, e.message, e.backtrace.join("\n")])
          end
          @sending_queue.push(msg)
        end
        @worker_pool.invoke(task)
      else
        # method not found
        @logger.debug ": called: Method not found: #{name} : #{uid} "
        @sending_queue.push(EPCErrorMessage.new(uid, "Not found the name: #{name}"))
      end # if
      @logger.debug ": called: Leave: #{name} : #{uid}"
    end

    # 相手から返り値が返ってきた
    def _return(ast)
      _, uid, value = ast
      @logger.debug ": return: Start: #{uid} : value = #{value}"
      if @session[uid] then
        _session_return(uid, nil, value)
      else
        @logger.error "Not found a session for #{uid}"
      end
      @logger.debug ": return: End: #{uid}"
    end

    # 相手からアプリケーションエラーが返ってきた
    def _return_error(ast)
      _, uid, error = ast
      @logger.debug ": return-error: Start: #{uid} : error = #{error}"
      if @session[uid] then
        # error : [classname, message, backtrace]
        _session_return(uid, EPCRuntimeError.new(error[0], error[1], error[2]), nil)
      else
        @logger.error "Not found a session for #{uid}"
      end
      @logger.debug ": return-error: End: #{uid}"
    end

    # 相手からEPCエラーが返ってきた
    def _epc_error(ast)
      _, uid, error = ast
      @logger.debug ": epc-error: Start: #{uid} : error = #{error}"
      if @session[uid] then
        # error : [classname, message, backtrace]
        _session_return(uid, EPCStackError.new(error[0], error[1], error[2]), nil)
      else
        @logger.error "Not found a session for #{uid}"
      end
      @logger.debug ": epc-error: End: #{uid}"
    end

    # 相手から一覧要求があった
    def _query_methods(ast)
      _, uid = ast
      @logger.debug ": query-methods: Start: #{uid}"
      begin
        list = @methods.map do |k,m|
          [m.name, m.argdoc, m.docstring]
        end
        msg = ReturnMessage.new(uid, list)
        @sending_queue.push(msg)
      rescue => e
        @logger.warn ": query-method: Exception #{e.message}"
        @logger.warn e.backtrace.join("\n")
        msg = ErrorMessage.new(uid, [e.class.name, e.message, e.backtrace.join("\n")])
        @sending_queue.push(msg)
      end
      @logger.debug ": query-methods: End: #{uid}"
    end

  end # class RPCService


  ## タスク処理用のスレッドプール
  
  class WorkerPool 

	def initialize(num, logger)
      @logger = logger
	  @job_queue = Queue.new
	  @worker_threads = []
	  num.times {
		@worker_threads << Thread.start(@job_queue, @logger) { |queue, logger|
          logger.debug("Worker Start")
		  loop {
            begin
              job = queue.shift
              logger.debug "Worker Thread : Job #{job}"
              break if job.nil?
              job.call
            rescue => e
              logger.error "Worker Error >>"
              logger.error e
            end
		  }
          logger.debug("Worker Exit")
		}
	  }
	end

	def invoke(job)
      if @worker_threads.size == 0 then
        @logger.debug "Worker : Ignore #{job}"
        return
      end
	  @job_queue << job
	end

	def kill
	  @worker_threads.size.times {
		invoke(nil)
	  }
      @worker_threads.each {|t| t.join }
	  @worker_threads.clear
	end

  end

end
