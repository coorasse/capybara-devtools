# frozen_string_literal: true

require "uri"
require "capybara/spec/spec_helper"
require "capybara/devtools"

CHROME_PATH = ENV.fetch("CHROME_PATH", "/usr/bin/chromium")

Capybara.register_driver :devtools_test do |app|
  Capybara::Devtools::Driver.new(app, browser_path: CHROME_PATH, browser_options: { "no-sandbox" => nil })
end

RSpec.configure do |config|
  Capybara::SpecHelper.configure(config)
  config.filter_run_when_matching :focus
end
