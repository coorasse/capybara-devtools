# frozen_string_literal: true

module Capybara
  module Devtools
    class Error < StandardError; end

    # Raised when a node reference belongs to a previous document or was detached.
    class ObsoleteNode < Error; end

    # Raised when the execution context went away while a command ran, e.g. during navigation.
    class ContextLost < Error; end

    class InvalidSelector < Error; end

    # Raised when the point to click is covered by another element.
    class MouseEventFailed < Error; end

    class JavaScriptError < Error
      attr_reader :class_name

      def initialize(message, class_name = nil)
        super(message)
        @class_name = class_name
      end
    end

    class ScriptTimeoutError < JavaScriptError; end

    class NoSuchWindowError < Error; end
  end
end
