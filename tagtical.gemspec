Gem::Specification.new do |s|
  s.name = %q{tagtical}
  s.version = "1.6.5.pre"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Aryk Grosz"]
  s.date = %q{2012-02-23}
  s.description = %q{Tagtical allows you do create subclasses for Tag and add additional functionality in an STI fashion. For example. You could do Tag::Color.find_by_name('blue').to_rgb. It also supports storing weights or relevance on the taggings.}
  s.email = %q{aryk@mixbook.com}
  s.extra_rdoc_files = [
    "README.rdoc"
  ]
  s.files = Dir["{rails,generators,lib}/**/*"] + ["MIT-LICENSE", "Rakefile", "README.rdoc", "CHANGELOG", "VERSION"]
  s.homepage = %q{https://github.com/Mixbook/tagtical}
  s.require_paths = ["lib"]
  s.summary = %q{Tagtical is a tagging plugin for Rails that provides weighting, contexts, and inheritance for tags.}

  s.test_files = Dir["spec/**/*"]

  s.add_dependency "rails"

  s.add_development_dependency "sqlite3"
  s.add_development_dependency "mysql"
  s.add_development_dependency "rspec"
end
