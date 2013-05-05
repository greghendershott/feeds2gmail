# Feeds2Gmail

Similar to the venerable rss2email, but:

1. Creates emails directly in your Gmail account using IMAP
    APPEND. This has a number of advantages over sending emails:

    - Faster.

    - No chance to be flagged as Spam.

    - No other deliverability issues.

    - Can place directly in appropriate mailbox (a.k.a. folder
      a.k.a. label). Speaking of which...

2. Each email is put in two IMAP mailboxes -- in Gmail, that means it
    is tagged with two labels -- `Feeds` and `Feeds/<feed-name>`.
    This way, you can read a mix of feeds, or, focus on posts from just
    one feed. Much like you could in Google Reader.

3. Obviously IMAP means you can read feeds on multiple devices, and
    they'll stay in sync:

    - The posts.

    - Which posts you've read.

    - Which posts you've starred.

    Editorial: This works so well, it makes you wonder why Google didn't
    add this to Gmail. It could make one suspect that this was never
    really about the viability of Google Reader; instead, a desire to kill
    RSS and Atom feeds in favor of proprietary monocultures like Twitter,
    Facebook, and maybe oh say Google+.

4. Written in Racket rather than in Python.

> Note: I _almost_ got this working as a Google Apps Script. That would
have let this run using GAS scheduling, without you having to schedule
run it on some computer of your own. The hitch?  There is nothing like
IMAP APPEND (letting you specify a folder) available in the Google
Apps Script environment.

# Install

This requires Racket 5.3.4 because the `net/imap` `imap-append`
function was updated to take an optional list of flags. We need this
so we can set the flags to '(), rather than the default '(\Seen), and
have the post emails should up as unread rather than read.

This requires `#lang rackjure` and `http` packages not supplied with
Racket. To install:

$ raco pkg install rackjure
$ raco pkg install http

# Configure

Create a `.feeds2gmail` file in your home directory:

```sh
email = <you>@gmail.com
password = <password>
```

# Feeds

Run this with the `--import-feeds <file>` flag to add feeds from
_file_, which should have one feed URI per line. URIs must be a full
URI including scheme, e.g. `http://www.example.com` not just
`www.example.com`.

# Environment

I run this on Amazon EC2 using Amazon Linux 64-bit using the Racket
build for Fedora 12 x64. The crontab runs it `@hourly`.

# Gmail not IMAP

I coded this to be Gmail-specific because that seems like the main use
case -- people wanting a Google Reader replacment. However there's
very little that's Gmail-specific. Mainly this lets the `.feeds2gmail`
config file not need to specify a few IMAP connection settings. If
you'd use this with another IMAP server, please either let me know and
I'll try to add, or, submit a pull request which I'd happily accept.
