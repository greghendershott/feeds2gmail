#lang rackjure

(require net/imap
         "db.rkt"
         "imap.rkt"
         "feed.rkt"
         "config.rkt")

(module+ test
  (require rackunit))

(define (update imap)
  (~> (load-feeds)
      (update-feeds imap)
      save-feeds
      void))

(define imap-path-delim (make-parameter "/"))

(define (update-feeds feeds imap)
  (parameterize ([imap-path-delim (imap-get-hierarchy-delimiter imap)])
    (for/fold ([feeds feeds])
              ([(uri feed) (in-hash feeds)])
      (define x (get-feed uri (feed-mod feed)))
      (cond [x (for/fold ([feeds (set-feed-mod feeds uri
                                               (fetched-feed-last-mod x))])
                          ([item (in-list (fetched-feed-items x))])
                 (define id (feed-item-id item))
                 (define dt (feed-item-date item))
                 (cond [(have-post? feeds uri id dt) feeds]
                       [else (email imap (feed-mailbox feed) item)
                             (~> (add-post feeds uri id dt)
                                 save-feeds)]))]
            [else feeds]))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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

(define (child->full child)
  (str (feeds-mailbox)
       (imap-path-delim)
       child))

(module+ test
    (parameterize ([feeds-mailbox "Feeds"]
                   [imap-path-delim "/"])
      (check-equal? (child->full "Foo")
                  "Feeds/Foo")))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (email imap mailbox item)
  ;; Format the email message
  (define ct (match (feed-item-content-type item)
               [(or "html" "xhtml") "text/html"]
               ["text" "text/plain"]
               [_ "text/plain"]))
  (define s 
    (str "Date: " (feed-item-date item) "\r\n"
         "From: \"" mailbox "\" <x@example.com>\r\n"
         "To: " (user) "\r\n"
         "Subject: " (feed-item-title item) "\r\n"
         "Content-Type: " ct "\r\n"
         "\r\n"
         (match ct
           ["text/html"
            (match (feed-item-content item)
              [(pregexp "<html>(.*)</html>" (list _ x))
               (format "<html>~a<p><a href=\"~a\">Original</a>.</p></html>"
                       x
                       (feed-item-link item))]
              [_
               (format "~a<p><a href=\"~a\">Original</a>.</p>"
                       (feed-item-content item)
                       (feed-item-link item))])]
           ["text/plain" (str  (feed-item-content item) "\r\n"
                               "Original: <" (feed-item-link item) ">\r\n")])))
  (when (send-email?)
    (define (send imap mailbox msg)
      (void (imap-get-expunges imap)) ;required, although docs don't say so
      (imap-append imap mailbox msg '())) ;do NOT use default \Seen
    ;; 1. Parent Feeds mailbox
    (send imap (feeds-mailbox) s)
    ;; 2. Child per-feed mailbox
    (send imap mailbox s)
    (printf "New: \"~a\"\n" (feed-item-title item))))
                 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (--update)
  (with-gmail-imap update))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Note: If feed already exists, this will erase all history for it!
(define (--add-feed uri)
  (define f (get-feed uri))
  (when f
    (define mailbox (~> f fetched-feed-title valid-mailbox-name child->full))
    (with-gmail-imap (lambda (imap)
                       ;; 1. Create parent Feeds mailbox
                       (idempotent-create-mailbox imap (feeds-mailbox))
                       ;; 2. Create child per-feed mailbox
                       (idempotent-create-mailbox imap mailbox)))
    (~> (load-feeds)
        (add-feed uri mailbox)
        save-feeds
        (void))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Import feed URIs from file, one per line.
(define (--import-feeds file)
  (for ([uri (file->lines file)])
    (--add-feed uri)))

;; TO-DO: Import OPML files?

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Parameters for command-line options

(define send-email? (make-parameter #t))
(define feeds-mailbox (make-parameter "Feeds"))

(module+ main
  ;; Use a LOCK file to prevent us from running more than one instance.
  ;; The current db.rkt interface isn't safe for this case. If someone
  ;; .e.g ran us to --add-feed while we were already running --update,
  ;; an incoherent cache.rktd might result.
  (define lf (build-path (find-system-path 'home-dir) ".feeds2gmail.LOCK"))
  (when (file-exists? lf)
    (eprintf "Alredy running (~a exists)\n" lf)
    (exit 1))
  (with-output-to-file lf (curry write "LOCK"))
  ;; Set an exit-handler to remove LOCK file, then call original
  ;; exit-handler. Why cover `exit`? For example `command-line` will
  ;; call exit for --help. If we don't catch, LOCK file will remain.
  (define old-exit-handler (exit-handler))
  (exit-handler (lambda (v)
                  (delete-file lf)
                  (old-exit-handler v)))
  (with-handlers ([values (lambda (exn)
                            (eprintf "~a\n" (exn-message exn))
                            (exit 1))])
    (command-line
     #:once-each
     [("--no-mail")
      (""
       "When used with --update, posts are remembered but not mailed"
       "to the IMAP account. Use case: First-time setup if you don't"
       "want old posts from the feeds to be mailed.")
      (send-email? #f)]
     [("-u" "--update")
      (""
       "Update feeds, adding new posts to IMAP account."
       "Hint: This is the option you'd want to use when running on a"
       "schedule with e.g. cron.")
      (--update)]
     #:multi
     [("-a" "--add-feed") feed-uri
      (""
       "Add a new feed."
       "<feed-uri> must start with the scheme ('http:' or 'https:').")
      (--add-feed feed-uri)]
     [("-i" "--import-feeds") /path/to/file
      (""
       "Import feeds from a plain text file, one feed URI per line."
       "Each URI must start with the scheme ('http:' or 'https:').")
      (--import-feeds /path/to/file)])
    (exit 0)))
  
