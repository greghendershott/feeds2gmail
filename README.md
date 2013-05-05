# Feeds2Gmail

Similar to the venerable rss2email, but:

## Creates emails directly in your Gmail account using IMAP APPEND.

This has a number of advantages over sending emails:

- Faster.

- No chance to be flagged as Spam.

- No other deliverability issues.

- Can place directly in appropriate mailbox (a.k.a. folder
  a.k.a. label). Speaking of which...

## Each email is put in two special IMAP mailboxes

In Gmail, that means each post is tagged with two labels -- `Feeds`
and `Feeds/<feed-name>`.
   
This way, you can read a mix of feeds, or, focus on posts from just
one feed. Much like you could in Google Reader.

## Multiple devices

IMAP means you can read feeds on multiple devices, and keep in sync:

- The posts.

- Which posts you've read.

- Which posts you've starred.

## Written in Racket rather than in Python.

Just because I love Racket.

> Note: I _almost_ got this working as a Google Apps Script. That would
have let this run using GAS scheduling, without you having to schedule
run it on some computer of your own. The hitch?  There is nothing like
IMAP APPEND (letting you specify a folder) available in the Google
Apps Script environment.

# Editorial

Using Gmail for this this works so well, it makes you wonder why
Google didn't do this.

Maybe Google's decision to shut off Google Reader was never really
about viability and maintenace costs. Instead, maybe the motivation
was deprecating RSS and Atom feeds in favor of proprietary
monocultures like Twitter, Facebook, and maybe oh say Google+.

# Install

This requires Racket 5.3.4 because the `net/imap` `imap-append`
function was updated to take an optional list of flags. We need this
so we can set the flags to `'()`, rather than the default `'(\Seen)`;
that way the post emails appear as unread rather than read.

This requires `#lang rackjure` and `http` packages not supplied with
Racket. To install:

```sh
$ raco pkg install rackjure
$ raco pkg install http
```

# Configure

Create a `.feeds2gmail` file in your home directory:

```sh
email = <you>@gmail.com
password = <password>
```

# Adding feeds

## Add one

Run with `--add-feed <feed-uri>` to add a single feed. URIs must be a
full URI including scheme, e.g. `http://www.example.com` not just
`www.example.com`.

## Import many

Run with the `--import-feeds <file>` flag to add feeds from _file_,
which should have one feed URI per line. URIs must be a full URI
including scheme, e.g. `http://www.example.com` not just
`www.example.com`.

# Environment

I run this on Amazon EC2 using Amazon Linux 64-bit using the Racket
build for Fedora 12 x64. The crontab runs it `@hourly`.

# Why Gmail not IMAP?

I coded this to be Gmail-specific because that seems like the main use
case -- people wanting a Google Reader replacment. However there's
very little that's Gmail-specific. Mainly this lets the `.feeds2gmail`
config file not need to specify a few IMAP connection settings. If
you'd use this with another IMAP server, please either let me know and
I'll try to add, or, submit a pull request which I'd happily accept.
