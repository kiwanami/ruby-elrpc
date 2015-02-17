# Elrpc : EPC (RPC Stack for Emacs Lisp) for Ruby

EPC is an RPC stack for Emacs Lisp and Elrpc is an implementation of EPC in Ruby.
Using elrpc, you can develop an emacs extension with Ruby code.

- https://github.com/kiwanami/emacs-epc

## Sample Code

### Ruby code (child process)

This code will be started by the parent process.

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

### Emacs Lisp code (parent process)

This elisp code calls the child process.
The package `epc` is required.

```el
(require 'epc)

(let (epc)
  ;; start a child process (using bundle exec)
  (setq epc (epc:start-epc "bundle" '("exec" "ruby" "echo.rb")))

  (deferred:$
    (epc:call-deferred epc 'echo '("hello"))
    (deferred:nextc it 
      (lambda (x) (message "Return : %S" x))))

  (message "%S" (epc:call-sync epc 'echo '(world)))

  (epc:stop-epc epc)) ; just `eval-last-sexp' here
```

### Ruby code (parent process)

You can also write the parent process code in Ruby.

```ruby
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

Please see the EPC document for the overview of EPC stack and protocol details.

- [EPC Readme](https://github.com/kiwanami/emacs-epc)

Please see the `elparser` document for object serialization.

- [elparser Readme](https://github.com/kiwanami/ruby-elparser)

### Start EPC

### Stop EPC

### Define Remote Method

### Call Remote Method

### Error Handling

### Utilities

### Define Server

### Debug

## License

Elrpc is licensed under MIT.

----
(C) 2015 SAKURAI Masashi. m.sakurai at kiwanami.net
