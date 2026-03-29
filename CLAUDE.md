# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
bundle exec rake test                    # Run all tests
bundle exec ruby -Ilib:test test/base/base_test.rb  # Run single test file
bundle exec rubocop                      # Lint
bundle exec rubocop -A                   # Auto-fix lint issues
bundle exec rbs-inline --output sig lib/ # Generate RBS from annotations
bundle exec steep check                  # Type check
bundle exec rake console                 # Interactive console
```

## Architecture

Single-file library (`lib/simple-rss.rb`) using regex-based XML parsing for flexibility with malformed feeds.

**Tag Syntax** (extend via `SimpleRSS.item_tags <<`):
- `tag` - simple element extraction
- `tag#attr` - attribute value (e.g., `media:content#url` → `media_content_url`)
- `tag+rel` - rel attribute matching (e.g., `link+alternate` → `link_alternate`)

**Dynamic Accessors**: Feed tags become `attr_reader` methods at parse time. Item tags are hash keys with `method_missing` for dot notation.

## Type Annotations

Uses RBS inline syntax:
```ruby
# @rbs (String, Integer) -> Bool   # method signature
attr_reader :name #: String         # attribute type
@items = [] #: Array[untyped]       # inline variable
```

## Release

Before tagging a release, bump the version in both files:
- `simple-rss.gemspec` (`s.version`)
- `lib/simple-rss.rb` (`VERSION`)

Both values must match. If they do not, CI may build and attempt to push the wrong gem version.

Then tag with `v*` to trigger automated RubyGems release:
```bash
git tag -a v1.3.4 -m "v1.3.4" && git push origin v1.3.4
```

Quick preflight checks:
```bash
grep -n "s.version" simple-rss.gemspec
grep -n "VERSION" lib/simple-rss.rb
gem build simple-rss.gemspec
```
