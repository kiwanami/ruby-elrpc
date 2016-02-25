(require 'epc)

(let (epc)
  ;; start a server process
  ;; bundle exec
  (setq epc (epc:start-epc "bundle" '("exec" "ruby" "sample.rb")))

  ;; system ruby
  ;;(setq epc (epc:start-epc "ruby" '("sample.rb")))

  ;; debug process (manual connection)
  ;;(setq epc (epc:start-epc-debug 8888))

  ;; asynchronous calling
  (deferred:$
    (epc:call-deferred epc 'echo '("hello"))
    (deferred:nextc it 
      (lambda (x) (message "Return : %S" x))))

  ;; synchronous calling (debug purpose)
  (message "%S" (epc:call-sync epc 'echo '(world)))

  (epc:call-sync epc 'inject '(0 + (1 2 3 4)))
  (epc:call-sync epc 'inject '(1 * (1 2 3 4)))
  (epc:call-sync epc 'inject '("" + ("1" "2" "3" "4")))

  ;; kill the server process
  (epc:stop-epc epc)
  )

;; just `eval-last-sexp' here
























