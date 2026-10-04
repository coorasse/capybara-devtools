# frozen_string_literal: true

require "ferrum"

module Capybara
  module Devtools
    # Owns the Chrome process (through Ferrum) and the open tabs.
    class Browser
      FERRUM_OPTIONS = %i[headless browser_path browser_options window_size timeout process_timeout
                          save_path logger ws_url url port host env proxy xvfb].freeze

      attr_reader :logs, :driver

      def initialize(driver, options)
        @driver = driver
        @options = options
        @logs = Logs.new
        @ferrum = nil
        @pages = {}
        @current_target_id = nil
      end

      def started?
        !@ferrum.nil?
      end

      def ferrum
        @ferrum ||= begin
          ferrum_options = @options.slice(*FERRUM_OPTIONS).merge(
            extensions: [{ source: JavaScript.source }],
            js_errors: false,
            pending_connection_errors: false
          )
          Ferrum::Browser.new(**ferrum_options)
        end
      end

      def current_page
        page_for(current_target_id)
      end

      def current_target_id
        @current_target_id ||= default_target.id
      end

      def window_handles
        default_context.instance_variable_get(:@targets).values.select(&:page?).map(&:id)
      end

      def switch_to(target_id)
        raise NoSuchWindowError, "no window with handle #{target_id}" unless window_handles.include?(target_id)

        @current_target_id = target_id
      end

      def open_new_window
        target = default_context.create_target
        target.maybe_sleep_if_new_window
        page_for(target.id)
        target.id
      end

      # The target is dropped from the context right away: Chrome reports the destruction asynchronously
      # and Capybara checks `window_handles` immediately after closing.
      def close_window(target_id)
        target = find_target(target_id)
        raise NoSuchWindowError, "no window with handle #{target_id}" unless target

        page = @pages.delete(target_id)
        (page&.ferrum || target.page).close
        default_context.delete_target(target_id)
      end

      def reset!(clear_local_storage: true, clear_session_storage: true)
        main = window_handles.first
        (window_handles - [main]).each { |handle| close_window(handle) }
        @current_target_id = main
        page = current_page
        page.reset_state
        unless page.ferrum.current_url.to_s.start_with?("about:")
          page.evaluate(storage_clear_script(clear_local_storage, clear_session_storage))
        end
        page.ferrum.command("Network.clearBrowserCookies")
        page.ferrum.go_to("about:blank")
        # Ferrum records every request of the tab and scans that list on each network event; without
        # clearing it the bookkeeping grows with the suite and steals CPU from the app under test.
        page.ferrum.network.clear(:traffic)
      rescue Ferrum::DeadBrowserError
        quit
      end

      def quit
        @ferrum&.quit
      rescue Ferrum::Error
        nil
      ensure
        @ferrum = nil
        @pages = {}
        @current_target_id = nil
      end

      def page_for(target_id)
        @pages[target_id] ||= begin
          target = find_target(target_id)
          raise NoSuchWindowError, "no window with handle #{target_id}" unless target

          Page.new(driver, target.page).tap { |page| apply_window_size(page) }
        end
      end

      private

      def default_context
        ferrum.contexts.default_context
      end

      def default_target
        default_context.default_target
      end

      # Makes the viewport match the window size, otherwise headless Chrome keeps ~90px for its UI.
      def apply_window_size(page)
        width, height = @options[:window_size]
        page.ferrum.resize(width: width, height: height) if width && height
      rescue Ferrum::Error
        nil
      end

      def find_target(target_id)
        default_context.instance_variable_get(:@targets)[target_id]
      end

      def storage_clear_script(local, session)
        parts = []
        parts << "try { localStorage.clear() } catch (e) {}" if local
        parts << "try { sessionStorage.clear() } catch (e) {}" if session
        "(function(){ #{parts.join(";")} })()"
      end
    end
  end
end
