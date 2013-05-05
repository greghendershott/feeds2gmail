#lang rackjure

(require net/imap
         racket/date
         "config.rkt")

(provide with-gmail-imap
         idempotent-create-mailbox)

(define/contract (with-gmail-imap f)
  ((imap-connection? . -> . any) . -> . any)
  (parameterize ([imap-port-number 993])
    (let-values ([(imc total recent)
                  (imap-connect "imap.gmail.com" (user) (pwd) "INBOX"
                                #:tls? #t)])
      (with-handlers ([exn:fail? (lambda (exn)
                                   (displayln exn)
                                   (imap-force-disconnect imc))])
        (begin0 (f imc)
          (imap-disconnect imc))))))

(define (idempotent-create-mailbox imap mailbox)
  (unless (imap-mailbox-exists? imap mailbox)
    (printf "Creating mailbox: ~a\n" mailbox)
    (imap-create-mailbox imap mailbox)))  
