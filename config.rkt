#lang racket

(provide user pwd)

(define user (make-parameter ""))
(define pwd  (make-parameter ""))

(define (read-config)
  (define xs (file->lines (build-path (find-system-path 'home-dir)
                                      ".feeds2gmail")))
  (for ([x xs])
    (match x
      [(pregexp "^email\\s*=\\s*(\\S+)\\s*$" (list _ s)) (user s)]
      [(pregexp "^password\\s*=\\s*(\\S+)\\s*$" (list _ s)) (pwd s)]
      [else (void)])))

(read-config)
