# frozen_string_literal: true

require "spec_helper"

module TestSessions
  Devtools = Capybara::Session.new(:devtools_test, TestApp)
end

skipped = ENV.fetch("CAPYBARA_SKIP", "").split(",").map(&:to_sym)

Capybara::SpecHelper.run_specs TestSessions::Devtools, "devtools", capybara_skip: skipped do |example|
  case example.metadata[:full_description]
  when /#click_link can download a file$/
    skip "download dir not configured" unless Capybara.save_path
  end
end
