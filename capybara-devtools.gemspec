# frozen_string_literal: true

require_relative "lib/capybara/devtools/version"

Gem::Specification.new do |s|
  s.name = "capybara-devtools"
  s.version = Capybara::Devtools::VERSION
  s.authors = ["Alessandro Rodi"]
  s.summary = "Capybara driver talking to Chrome over the DevTools Protocol with one round trip per operation"
  s.license = "MIT"
  s.required_ruby_version = ">= 3.2"
  s.files = Dir["lib/**/*", "LICENSE", "README.md"]

  s.add_dependency "capybara", ">= 3.40"
  s.add_dependency "ferrum", ">= 0.15"
end
