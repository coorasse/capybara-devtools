# frozen_string_literal: true

require "uri"
require "capybara"
require "ferrum"
require "capybara/devtools/version"
require "capybara/devtools/errors"
require "capybara/devtools/javascript"
require "capybara/devtools/logs"
require "capybara/devtools/input"
require "capybara/devtools/page"
require "capybara/devtools/node"
require "capybara/devtools/browser"
require "capybara/devtools/driver"

Capybara.register_driver :devtools do |app|
  Capybara::Devtools::Driver.new(app)
end
