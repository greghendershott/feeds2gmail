#lang rackjure

(require racket/runtime-path)

(provide load-feeds 
         save-feeds
         add-feed
         delete-feed
         set-feed-mod
         have-post?
         add-post
         (struct-out feed)
         (struct-out post))

;; This is a database of the feeds. Each feed has a URI, a title, a
;; last-modification date string, and a collection of posts. Each post
;; has a UID and a date.  This is for the purpose of determining
;; whether we need to fetch the feed at all, and whether we already
;; know about each post in the latest version of the feed.

;; This is a 100% functional interface: Each function returns a
;; modified copy of the feeds "database".

;; Currently this is simply doing read/write serialization to a local
;; rktd file. But could change this implementation to use mysql,
;; Amazon Dynamo, Google Docs, or whatever.

(define feeds-path (build-path (find-system-path 'home-dir)
                               ".feeds2gmail.cache.rktd"))

(define/contract (load-feeds)
  (-> hash?) ;; (hashof uri string? feed?)
  (with-handlers ([exn:fail? (lambda (_) (hash))])
    (with-input-from-file feeds-path read)))

(define/contract (save-feeds feeds)
  (hash? . -> . hash?)
  (with-output-to-file feeds-path #:exists 'replace (curry pretty-write feeds))
  feeds)

(struct feed (mailbox mod posts) #:prefab)
(struct post (date) #:prefab)

(define/contract (add-feed feeds uri mailbox)
  (hash? string? string? . -> . hash?)
  (hash-set feeds uri (feed mailbox "NEVER" (hash))))

(define/contract (delete-feed feeds uri)
  (hash? string? . -> . hash?)
  (hash-remove feeds uri))

(define/contract (set-feed-mod feeds uri mod)
  (hash? string? (or/c #f string?) . -> . hash?)
  (hash-set feeds
            uri
            (struct-copy feed (hash-ref feeds uri) [mod mod])))
                
(define/contract (have-post? feeds uri id date)
  (hash? string? string? string? . -> . boolean?)
  (define f (hash-ref feeds uri))
  (and (hash-has-key? (feed-posts f) id)
       (let ([p (hash-ref (feed-posts f) id)])
         (and (equal? date (post-date p))))))

(define/contract (add-post feeds uri id date)
  (hash? string? string? string? . -> . hash?)
  (define f (hash-ref feeds uri))
  (hash-set feeds uri (feed (feed-mailbox f)
                            (feed-mod f)
                            (hash-set (feed-posts f) id (post date)))))

;; ;; Example
;; (~> (load-feeds)
;;     (~> (add-feed "feed0" "Title0")
;;         (add-post "feed0" "id0" "date")
;;         (add-post "feed0" "id1" "date")
;;         (set-feed-mod "feed0" "Today"))
;;     (~> (add-feed "feed1" "Title1")
;;         (add-post "feed1" "idA" "date")
;;         (add-post "feed1" "idB" "date"))
;;     save-feeds)
