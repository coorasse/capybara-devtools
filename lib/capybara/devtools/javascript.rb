# frozen_string_literal: true

module Capybara
  module Devtools
    module JavaScript
      DIR = File.expand_path("javascripts", __dir__)

      def self.source
        @source ||= File.read(File.join(DIR, "capybara_devtools.js"))
                        .sub("__IS_DISPLAYED_ATOM__", File.read(File.join(DIR, "is_displayed.min.js")).strip)
      end

      def self.html5_drag
        @html5_drag ||= File.read(File.join(DIR, "html5_drag.js"))
      end
    end
  end
end
