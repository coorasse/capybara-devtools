# capybara-devtools

A Capybara driver for Chrome that speaks the DevTools Protocol directly. No chromedriver, no HTTP
and JSON wire protocol: Ferrum provides the browser process and the WebSocket, and every Capybara
operation is one `Runtime.evaluate` into a small runtime injected in each document. Finding
elements, checking visibility and filtering by text happen in that single call.

It passes Capybara's shared driver suite (1541 examples) and is a drop-in replacement for
`:selenium_chrome_headless` in a Rails test suite.

## Usage

```ruby
# Gemfile, group :test
gem "capybara-devtools"

# spec/rails_helper.rb
require "capybara/devtools"

Capybara.register_driver :devtools_chrome_headless do |app|
  Capybara::Devtools::Driver.new(
    app,
    browser_path: "/path/to/chrome-headless-shell",   # optional, defaults to the chrome found on PATH
    window_size: [1920, 1080],
    browser_options: { "no-sandbox" => nil }
  )
end

RSpec.configure do |config|
  config.before(:each, :js, type: :system) { driven_by :devtools_chrome_headless }
end
```

Options: `headless` (default true), `browser_path`, `browser_options` (hash of Chrome flags),
`window_size`, `timeout` (seconds per protocol command, default 10), `process_timeout`,
`save_path` (download directory, defaults to `Capybara.save_path`), `clear_local_storage` and
`clear_session_storage` (default true, applied on `reset!`), `screen_size` (used by
`maximize_window`).

`page.driver.browser.logs.get(:browser)` returns console errors and warnings, uncaught
exceptions and failed resource loads with `level` (`SEVERE`, `WARNING`, `INFO`) and `message`,
compatible with code written for Selenium's browser log.

## How it stays fast and correct

- One protocol round trip per operation (under 0.1 ms locally), `find` included: the matching
  nodes come back with their visibility, position and the document token in that call. Mouse and
  key events that are followed by another one are sent without waiting for their response.
  Selenium needs one HTTP request per step plus chromedriver's own work.
- Typing sends real key events (`Input.dispatchKeyEvent`); values longer than 30 characters use
  `Input.insertText` for the middle part, like Capybara's Selenium driver does in rapid mode.
  Set `Capybara.default_set_options = { rapid: true }` to always use it.
- Clicks are real mouse events at the element's centre. Before clicking, the driver waits (up to
  one second) for CSS transitions and animations that move the element to finish, and checks that
  the point really hits the element, scrolling it to the middle of the viewport once if not.
  A click that would land on another element raises `Capybara::Devtools::MouseEventFailed`, which
  Capybara retries like a stale element.
- Visibility uses the same Selenium `isDisplayed` atom as the Selenium driver.
- Element references are tied to the document they were found in, so references from a previous
  page raise `Capybara::Devtools::ObsoleteNode` instead of pointing at the wrong element.

## Development

```
bundle install
bundle exec rspec            # Capybara's shared driver suite against headless Chromium
CHROME_PATH=/path/to/chrome bundle exec rspec
```
