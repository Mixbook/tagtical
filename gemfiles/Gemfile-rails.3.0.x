source "https://rubygems.org"

gemspec :path => ".."

gem "rails", "~> 3.0.0"

group :test do
  gem "mocha"
end
