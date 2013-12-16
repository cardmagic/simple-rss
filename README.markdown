## Welcome to Simple RSS

Simple RSS is a simple, flexible, extensible, and liberal RSS and Atom reader
for Ruby. It is designed to be backwards compatible with the standard RSS
parser, but will never do RSS generation.

## Download

* gem install simple-rss
* https://github.com/cardmagic/simple-rss
* git clone git@github.com:cardmagic/simple-rss.git

### Usage
The API is similar to Ruby's standard RSS parser:

    require 'rubygems'
    require 'simple-rss'
    require 'open-uri'

    rss = SimpleRSS.parse open('http://slashdot.org/index.rdf')

    rss.channel.title # => "Slashdot"
    rss.channel.link # => "http://slashdot.org/"
    rss.items.first.link # => "http://books.slashdot.org/article.pl?sid=05/08/29/1319236&amp;from=rss"

But since the parser can read Atom feeds as easily as RSS feeds, there are optional aliases that allow more atom like reading:

    rss.feed.title # => "Slashdot"
    rss.feed.link # => "http://slashdot.org/"
    rss.entries.first.link # => "http://books.slashdot.org/article.pl?sid=05/08/29/1319236&amp;from=rss"

The parser does not care about the correctness of the XML as it does not use an XML library to read the information. Thus it is flexible and allows for easy extending via:

    SimpleRSS.feed_tags << :some_new_tag
    SimpleRSS.item_tags << :"item+myrel" # this will extend SimpleRSS to be able to parse RSS items or ATOM entries that have a rel specified, common in many blogger feeds
    SimpleRSS.item_tags << :"feedburner:origLink" # this will extend SimpleRSS to be able to parse RSS items or ATOM entries that have a specific pre-tag specified, common in many feedburner feeds
    SimpleRSS.item_tags << :"media:content#url" # this will grab the url attribute of the media:content tag 

## Authors

* Lucas Carlson  (mailto:lucas@rufy.com)
* Herval Freire (mailto:hervalfreire@gmail.com)

Inspired by [Blagg](http://www.raelity.org/lang/perl/blagg) from Rael Dornfest.

This library is released under the terms of the GNU LGPL.

