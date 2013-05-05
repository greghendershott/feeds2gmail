#lang rackjure

(require xml
         http/request
         http/head
         net/head
         openssl/sha1)

(provide get-feed
         (struct-out fetched-feed)
         (struct-out feed-item))

(module+ test
  (require rackunit))

(struct fetched-feed (title last-mod items))
(struct feed-item (uri id date title link content content-type))

(define/contract (get-feed uri [last-mod #f])
  ((string?) ((or/c #f string?)) . ->* . (or/c #f fetched-feed?))
  (with-handlers ([exn:fail? (lambda (exn)
                               (displayln uri) 
                               (displayln (exn-message exn))
                               #f)])
    (printf "~a ... " uri)
    (call/input-request ;;this handles 301 302 redirects automatically
     "1.0" "GET" uri
     {'Connection: "close"
      'If-Modified-Since (or last-mod "")
      'Content-Type "application.xml"}
     (lambda (in h)
       (printf "~a ~a\n" (extract-http-code h) (extract-http-text h))
       (match (extract-http-code h)
         [200 (with-handlers ([exn:xml? (lambda (exn)
                                          (displayln uri)
                                          (displayln (exn-message exn))
                                          #f)])
                (~> (read-entity/transfer-decoding-port in h)
                    read-xml->xexpr
                    (parse-feed uri (extract-field "Last-Modified" h))))]
         [else #f])))))

(define (read-xml->xexpr in) ;; input-port? -> xexpr?
  (define (remove-whitespace x)
    ((eliminate-whitespace '(feed entry rss channel item rdf:RDF)) x))
  (~> in read-xml document-element remove-whitespace xml->xexpr convert-cdata))

(define (convert-cdata x) ;; xexpr? -> xexpr?
  (match x
    [`(,tag (,as ...) ,els ...)
     `(,tag (,@as) ,@(for/list ([el els])
                       (convert-cdata el)))]
    [(cdata (location _ _ _)
            (location _ _ _)
            (pregexp "^<!\\[CDATA\\[(.*)\\]\\]>$" (list _ s))) s]
    [else x]))

(module+ test
  (check-equal?
   (convert-cdata `(html ([a "a"][b "b"]) 
                         (body ()
                               ,(cdata (location 0 0 0)
                                       (location 0 0 0)
                                       "<![CDATA[testing]]>")
                               (p () "foo" "bar"))))
   '(html ((a "a") (b "b"))
          (body ()
                "testing"
                (p () "foo" "bar")))))

(define/contract (parse-feed x uri last-mod)
  (xexpr? string? (or/c #f string?) . -> . fetched-feed?)
  (define (filter-non-#f/reverse xs)
    (~> (filter values xs) reverse))
  (define (->html-string xs)
    (apply str (for/list ([x (in-list xs)])
                 (match x
                   [(? string?) x]
                   [(? number?) (str "&#" x ";")]
                   [(? xexpr?) (xexpr->string x)]))))
  (define (->plain-string xs)
    (apply str (for/list ([x (in-list xs)])
                 (match x
                   [(? string?) x]
                   [(? number?) (make-string 1 (integer->char x))]))))
  (define (feed-item* id date titles hrefs contents content-type)
    (feed-item uri
               id
               date
               (regexp-replace* #rx"\r\n|\r|\n"
                               (->plain-string titles)
                               "\r\n\t")
               (->html-string hrefs)
               (->html-string contents)
               content-type))
  (match x
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; Atom?
    [`(feed ,(list-no-order `[xmlns "http://www.w3.org/2005/Atom"] _ ...)
            ,xs ...)
     (fetched-feed
      (match xs
        [(list-no-order `(title (,_ ...) ,ss ...) _ ...)
         (->plain-string ss)]
        [else ""])
      last-mod
      (filter-non-#f/reverse
       (for/list ([x xs])
         (match x
           [`(entry () ,xs ...)
            (match xs
              [(list-no-order
                `(id ([,_ ,_] ...) ,id)
                `(title ([,_ ,_] ...) ,titles ...)
                (or `(link ,(list-no-order
                             `[href ,hrefs ...]
                             `[rel "alternate"]
                             _ ...))
                    `(link ([href ,hrefs ...])))
                `(updated () ,date)
                (or `(content ,(list-no-order `[type ,type] _ ...)
                              ,contents ...)
                    `(summary ,(list-no-order `[type ,type] _ ...)
                              ,contents ...))
                _ ...)
               (feed-item* id date titles hrefs contents type)]
              [else (displayln "Bad Atom entry")
                    ;;(pretty-print x)
                    #f])]
           [else #f]))))]
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; RSS?
    [`(rss ,as ...
           (channel () ,xs ...))
     (fetched-feed
      (match xs
        [(list-no-order `(title (,_ ...) ,ss ...) _ ...)
         (->plain-string ss)]
        [else ""])
      last-mod
      (filter-non-#f/reverse
       (for/list ([x xs])
         (match x
           [`(item ([,_ ,_] ...) ,xs ...)
            (match xs
              [(list-no-order
                `(title ([,_ ,_] ...) ,titles ...)
                `(link ([,_ ,_] ...) ,hrefs ...)
                (or `(content:encoded () ,contents ...)
                    `(description () ,contents ...))
                _ ...)
               (define pub
                 (match xs
                   [(list-no-order `(pubDate () ,s) _ ...) s]
                   [else "unspecified"]))
               (define id
                 (match xs
                   [(list-no-order `(guid () ,s) _ ...) s]
                   [else (~> (->html-string contents) open-input-string sha1)]))
               (feed-item* id pub titles hrefs contents "html")]
              [else (printf "Bad RSS item\n")
                    ;; (pretty-print x)
                    #f])]
           [else #f]))))]
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; RDF?
    [`(rdf:RDF ([,_ ,_] ...)
               ,xs ...)
     (fetched-feed
      (match xs
        [(list-no-order `(channel ([,_ ,_] ...) ,xs ...) _ ...)
         (match xs
           [(list-no-order `(title (,_ ...) ,ss ...) _ ...)
            (->plain-string ss)])])
      last-mod
      (filter-non-#f/reverse
       (for/list ([x xs])
         (match x
           [`(item ([,_ ,_] ...) ,xs ...)
            (match xs
              [(list-no-order
                `(title ([,_ ,_] ...) ,titles ...)
                `(link ([,_ ,_] ...) ,hrefs ...)
                `(description () ,contents ...)
                _ ...)
               (define pub
                 (match xs
                   [(list-no-order `(pubDate () ,s) _ ...) s]
                   [else "unspecified"]))
               (define id
                 (match xs
                   [(list-no-order `(guid () ,s) _ ...) s]
                   [else (~> (->html-string contents) open-input-string sha1)]))
               (feed-item* id pub titles hrefs contents "html")]
              [else (printf "Bad RDF item\n")
                    ;; (pretty-print x)
                    #f])]
           [else #f]))))]
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; ???
    [else (printf "Not an Atom, RSS, or RDF feed: ~a\n" uri)
          ;; (pretty-print x)
          (fetched-feed "Unknown" last-mod '())]))
