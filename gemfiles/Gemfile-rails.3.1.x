source "https://rubygems.org"

gemspec :path => ".."

gem "rails", "~> 3.1.0"

group :test do
  gem "mocha"
end
