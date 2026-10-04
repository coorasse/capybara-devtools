# frozen_string_literal: true

module Capybara
  module Devtools
    # Collects console output, uncaught exceptions and browser log entries so test suites can assert
    # on them the way they do with Selenium's `browser.logs.get(:browser)`.
    class Logs
      Entry = Struct.new(:level, :message, :timestamp)

      LEVELS = { "error" => "SEVERE", "assert" => "SEVERE", "warning" => "WARNING", "info" => "INFO" }.freeze

      def initialize
        @entries = []
        @mutex = Mutex.new
      end

      def get(_type = :browser)
        @mutex.synchronize do
          entries = @entries
          @entries = []
          entries
        end
      end

      def add(level, message)
        @mutex.synchronize { @entries << Entry.new(level, message, (Time.now.to_f * 1000).to_i) }
      end

      def subscribe(page)
        page.on("Runtime.exceptionThrown") do |params|
          details = params["exceptionDetails"]
          text = details.dig("exception", "description") || details["text"]
          add("SEVERE", "#{details["url"]} #{details["lineNumber"]}:#{details["columnNumber"]} #{text}")
        end

        page.on("Runtime.consoleAPICalled") do |params|
          level = LEVELS[params["type"]] || "INFO"
          message = Array(params["args"]).map { |arg| arg["description"] || arg["value"].to_s }.join(" ")
          add(level, message)
        end

        page.on("Log.entryAdded") do |params|
          entry = params["entry"]
          next if entry["source"] == "console-api"

          add(LEVELS[entry["level"]] || "INFO", "#{entry["url"]} - #{entry["text"]}")
        end
      end
    end
  end
end
