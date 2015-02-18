# Elrpc : EPC (RPC Stack for Emacs Lisp) for Ruby

EPC is an RPC stack for Emacs Lisp and Elrpc is an implementation of EPC in Ruby.
Using elrpc, you can develop an emacs extension with Ruby code.

- [EPC at github](https://github.com/kiwanami/emacs-epc)

## Sample Code

### Ruby code (server process)

This code is started by the client process, such as Emacs Lisp.

`echo.rb`
```ruby
require 'elrpc'

 # start server
server = Elrpc.start_server()

 # define a method
server.def_method "echo" do |arg|
  # just return the given argument value
  arg
end

 # sleep the main thread and wait for closing connection
server.wait
```

### Emacs Lisp code (client process)

This elisp code calls the server process.
The package `epc` is required.

`echo-client.el`
```el
(require 'epc)

(let (epc)
  ;; start a server process (using bundle exec)
  (setq epc (epc:start-epc "bundle" '("exec" "ruby" "echo.rb")))

  (deferred:$
    (epc:call-deferred epc 'echo '("hello"))
    (deferred:nextc it 
      (lambda (x) (message "Return : %S" x))))

  (message "%S" (epc:call-sync epc 'echo '(world)))

  (epc:stop-epc epc)) ; just `eval-last-sexp' here
```

### Ruby code (client process)

You can also write the client process code in Ruby.

`echo-client.rb`
```ruby
require 'elrpc'

 # start a server process
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
 # kill the server process
cl.stop
```

Here is the result.

```
$ bundle exec ruby echo-client.rb
1 hello
2 wait
3 world
4 ok
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'elrpc'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install elrpc

## API Document

### EPC Overview

The EPC uses a peer-to-peer-architecture. After the connection is established, both peers can define remote methods and call the methods at the other side.

Let we define the words *server* and *client*. *Server* is a process which opens a TCP port and waiting for the connection. *Client* is a process which connects to the *server*. In most cases, a *client* process starts a *server* process. Then, the *server* process provides some services to the *client* process.

This diagram shows the API usage and the relation of processes.

![API Overview](https://raw.githubusercontent.com/kiwanami/emacs-epc/master/img/Overview.png)

Please see the EPC document for the overview of EPC stack and protocol details.

- [EPC Readme](https://github.com/kiwanami/emacs-epc)

Please see the `elparser` document for object serialization.

- [elparser Readme](https://github.com/kiwanami/ruby-elparser)

### Building Server-Process

- Module method : `Elrpc::start_server(methods = [], port = 0)`
    - Arguments
        - `methods` : Array of `Elrpc::Method` instances.
        - `port` : TCP Port number. 0 means that the number is decided by OS.
    - Return
        - A `Elrpc::RPCService` instance


*Sample Code*
```ruby
server = Elrpc::start_server
```


### Defining Remote Method

- `Elrpc::RPCService#def_method(name, argdoc=nil, docstring=nil, &block)`
    - Arguments
        - `name` : String. Method name which is referred by the peer process.
        - `argdoc` : String[optional]. Argument information for human.
        - `docstring` : String[optional]. Method information for human.
        - `&block` : Block. Code block which is called by the peer process. The return value is serialized and sent to the peer.

The return value of the code block is serialized and sent to the peer process. So, if the return value includes wrong values which can't be serialized by `elparser`, the runtime exception `EPCStackError` is thrown to the method calling of the peer process.

*Sample Code*
```ruby
server.def_method("echo") do |arg|
    arg
end

server.def_method("add") do |a, b|
    a + b
end

server.def_method("inject", 
    "init(initial value), op(operator symbol), list", 
    "Apply Enumerable#inject method.") do |init, op, list|
    list.inject(init, op)
end
```

### Calling Remote Method

If the peer process defines some methods, the instance of `Elrpc::RPCService` can call the peer's method, regardless of the server process or the client one. (See the EPC document.)

- `Elrpc::RPCService#call_method(name, *args)`
    - Synchronous method calling. The current thread is blocked until the calling result is returned.
    - Arguments
        - `name` : String. Method name to call.
        - `args` : Array(Variable length arguments) Argument values.
    - Return
        - The return value which is returned by the peer process.
    - Exception
        - `EPCRuntimeError` : An exception which is thrown by the peer's method.
        - `EPCStackError` : An exception which is thrown by the EPC protocol stack.

- `Elrpc::RPCService#call_method_async(name, *args, &block)`
    - Asynchronous method calling. The current thread is not blocked. The calling result is passed to the code block.
    - Arguments
        - `name` : String. Method name to call.
        - `args` : Array(Variable length arguments) Argument values.
        - `block` : Block. 
    - Block Arguments
        - `err` : If `nil`, the method calling succeed and the return value is bounded by `value`. If not `nil`, an exception is thrown within the method calling.
            - `EPCRuntimeError` : An exception which is thrown by the peer's method.
            - `EPCStackError` : An exception which is thrown by the EPC protocol stack.
        - `value` : The return value which is returned by the peer process.

*Sample Code*
```ruby
puts server.call_method("echo", "hello")

server.call_method_async("echo", "hello") do |err, value|
    puts value
end

puts server.call_method("add", 1, 2)

server.call_method("add", 1, 2) do |err, value|
    puts value
end

puts server.call_method("inject", 0, :+, [1,2,3,4])
puts server.call_method("inject", 1, :*, [1,2,3,4])
```

### Utilities

- `Elrpc::RPCService#query_methods`
- `Elrpc::RPCService#query_methods_async`
    - Return
        - Array of method specs of the peer process.

*Sample Code*
```ruby
server.query_methods
 # => [[:echo, nil, nil], [:add, nil, nil], [:inject, "init, op, list", "Enumerable#inject"]]
```

### EPC Process

Elrpc can implement the client process which starts a server process. The server process can be implemented in Ruby and the other language, such as Perl, Python and Emacs Lisp.

- Module method `Elrpc::start_process(cmd)`
    - Argument
        - `cmd` : Array. Command line elements for the server process.
    - Return
        - An instance of `Elrpc::Service`.

*Sample Code*
```ruby
cl = Elrpc.start_process(["ruby","echo.rb"])

puts cl.call_method("echo", "1 hello")

cl.stop
```

## Development

In most cases, the client process is Emacs and the server one is implemented by Elrpc to extend Emacs functions in Ruby.
However, it may be difficult to develop the programs which belong to the different environment.
So, at first, it is better to implement both sides in Ruby and write tests.

If you want to watch the STDOUT and STDERR of the server process, start the process from command line and connect to the process with `irb` or `pry`, like following:

*Starting the server process*
```
$ bundle exec ruby echo.rb
12345
```

`12345` is port number to connect from the client process. The number changes each time.
Then, start `irb` in the another terminal.

*Connecting to the process from irb*
```
$ bundle exec irb
> require 'elrpc'
> cl = Elrpc.start_client(12345)
> cl.call_method("echo", "hello")
```

When you invoke `call_method`, the first terminal in which the server process runs, may show some output.

## Performance

EPC is designed for fast communication between Emacs and other processes.
Employing S-exp serialization and keeping TCP connection, EPC is faster than HTTP-based RPC, such as JSON-RPC.

Executing the benchmark program `test/echo-bench.rb`, You can check the performance in your environment. The program measures following aspects:

- round trip time of method invocation
    - synchronous/asynchronous calling
- string transportation
- array/list serialization and transportation
- hash/alist serialization and transportation

Here is the result on Lenovo X240 with Intel Core i7-4600U CPU 2.10GHz, 8GB RAM, ruby 2.1.4p265  x86_64-linux.

```
$ bundle exec ruby test/echo-bench.rb
                 user     system      total        real
int          0.180000   0.040000   0.220000 (  0.402582)
int_a        0.180000   0.010000   0.190000 (  0.205672)
string       0.390000   0.040000   0.430000 (  0.753418)
array        1.410000   0.070000   1.480000 (  2.687667)
hash         3.930000   0.070000   4.000000 (  7.632865)
(call/sec) int: 9090.9  int_async: 10526.3  string: 4651.2  array: 1351.4  hash: 500.0
```

In the condition Ruby to Ruby, `elrpc` can perform around 10000 call/sec.

## License

Elrpc is licensed under MIT.

----
(C) 2015 SAKURAI Masashi. m.sakurai at kiwanami.net
