#lang rackjure

(require net/imap
         racket/date
         "config.rkt")

(module+ test
  (require rackunit))

(provide with-gmail-imap
         idempotent-create-mailbox
         imap-path-delim
         valid-mailbox-name
         child->full)

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

(define imap-path-delim (make-parameter "/"))

(define (valid-mailbox-name name)
  (~> (match name [(pregexp "^\\s*(.+?)\\s*$" (list _ s)) s])
      (regexp-replaces
       `((#px"[^-A-Za-z0-9.,?:'\"()| ]" "")
         (,(imap-path-delim) "")
         (#px"[ ]{2,}" " ")))))

(module+ test
  (check-equal? (valid-mailbox-name " Foo ")
                "Foo")
  (check-equal? (valid-mailbox-name " stratēchery ")
                "stratchery"))

(define (child->full child feeds-mailbox)
  (str feeds-mailbox
       (imap-path-delim)
       child))

(module+ test
    (parameterize ([imap-path-delim "/"])
      (check-equal? (child->full "Foo" "Feeds")
                  "Feeds/Foo")))
