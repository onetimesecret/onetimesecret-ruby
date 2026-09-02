# `onetime` compatibility package

The canonical RubyGem for the OnetimeSecret Ruby client is now
[`onetimesecret`](https://rubygems.org/gems/onetimesecret).

Update your Gemfile:

```ruby
gem "onetimesecret", "~> 0.7.0"
```

The Ruby API remains under the `Onetime` namespace. Both
`require "onetimesecret"` and `require "onetime"` are supported by the
canonical package.

This package contains no implementation files. It depends on `onetimesecret`
so existing `onetime` users can transition without loading conflicting files.
