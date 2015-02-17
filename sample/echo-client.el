(require 'epc)

(let (epc)
  ;; start a child process
  ;; bundle exec
  (setq epc (epc:start-epc "bundle" '("exec" "ruby" "echo.rb")))

  ;; system ruby
  ;;(setq epc (epc:start-epc "ruby" '("_echo.rb")))

  ;; debug process (manual connection)
  ;;(setq epc (epc:start-epc-debug 8888))


  ;; asynchronous calling
  (deferred:$
    (epc:call-deferred epc 'echo '("hello"))
    (deferred:nextc it 
      (lambda (x) (message "Return : %S" x))))

  ;; synchronous calling (debug purpose)
  (message "%S" (epc:call-sync epc 'echo '(world)))

  ;; 
  (epc:stop-epc epc)
  )

;; just `eval-last-sexp' here
