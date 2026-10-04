# frozen_string_literal: true

module Capybara
  module Devtools
    class Driver < Capybara::Driver::Base
      DEFAULT_OPTIONS = {
        headless: true,
        window_size: [1280, 1024],
        timeout: 10,
        process_timeout: 20,
        clear_local_storage: true,
        clear_session_storage: true
      }.freeze

      attr_reader :app, :options

      def initialize(app, **options)
        super()
        @app = app
        @options = DEFAULT_OPTIONS.merge(options)
        @options[:save_path] ||= File.expand_path(Capybara.save_path) if Capybara.save_path
        @browser = nil
      end

      def browser
        @browser ||= Browser.new(self, @options)
      end

      def logs
        browser.logs
      end

      def wait?
        true
      end

      def needs_server?
        true
      end

      def invalid_element_errors
        [ObsoleteNode, ContextLost, MouseEventFailed, Ferrum::NodeNotFoundError, Ferrum::NoExecutionContextError]
      end

      def no_such_window_error
        NoSuchWindowError
      end

      # ---- navigation ----

      def visit(path)
        page.ferrum.go_to(path)
      end

      def refresh
        page.ferrum.refresh
      end

      def go_back
        page.ferrum.back
      end

      def go_forward
        page.ferrum.forward
      end

      def current_url
        page.ferrum.current_url
      end

      def title
        page.ferrum.title
      end

      def html
        page.ferrum.body
      end

      def status_code
        page.ferrum.network.status
      end

      def response_headers
        headers = page.ferrum.network.response&.headers
        return unless headers

        Hash.new { |hash, key| hash.fetch(key.to_s.downcase, nil) }.merge!(headers.transform_keys(&:downcase))
      end

      # ---- finding ----

      def find_xpath(selector, **hints)
        page.find(:xpath, selector, nil, hints)
      end

      def find_css(selector, **hints)
        page.find(:css, selector, nil, hints)
      end

      def active_element
        evaluate_script("document.activeElement")
      end

      # ---- scripts ----

      def execute_script(script, *args)
        page.run_script(script, native_args(args))
        nil
      end

      def evaluate_script(script, *args)
        page.run_script("return #{script}", native_args(args))
      end

      def evaluate_async_script(script, *args)
        page.run_script(script, native_args(args), async: true, wait: session_options.default_max_wait_time)
      end

      def send_keys(*)
        page.input.type(*)
      end

      def save_screenshot(path, **options)
        page.ferrum.screenshot(path: path, **options.slice(:full, :selector, :format, :quality, :scale))
      end

      # ---- frames ----

      def switch_to_frame(frame)
        case frame
        when :top then page.top_frame
        when :parent then page.pop_frame
        else page.push_frame(frame.native)
        end
      end

      def frame_title
        evaluate_script("document.title")
      end

      def frame_url
        evaluate_script("document.location.href")
      end

      # ---- windows ----

      def current_window_handle
        handle = browser.current_target_id
        raise NoSuchWindowError, "the current window was closed" unless browser.window_handles.include?(handle)

        handle
      end

      def window_handles
        browser.window_handles
      end

      def open_new_window(_kind = :tab)
        browser.open_new_window
      end

      def switch_to_window(handle)
        browser.switch_to(handle)
      end

      def close_window(handle)
        browser.close_window(handle)
      end

      def window_size(handle)
        within_window(handle) { evaluate_script("[window.outerWidth, window.outerHeight]") }
      end

      def resize_window_to(handle, width, height)
        within_window(handle) { page.ferrum.resize(width: width, height: height) }
      end

      def maximize_window(handle)
        resize_window_to(handle, *@options.fetch(:screen_size, [1920, 1080]))
      end

      def fullscreen_window(handle)
        within_window(handle) { page.ferrum.resize(fullscreen: true) }
      end

      # ---- modals ----

      def accept_modal(type, **options)
        page.expect_modal(true, type == :prompt ? options[:with] : nil)
        yield if block_given?
        page.find_modal(**options.slice(:text, :wait))
      end

      def dismiss_modal(_type, **options)
        page.expect_modal(false)
        yield if block_given?
        page.find_modal(**options.slice(:text, :wait))
      end

      # ---- lifecycle ----

      # Whether the browser has requests in flight, as far as its network events say, optionally
      # only those to URLs starting with `origin` (a font from a CDN can stay pending for a while).
      def pending_requests?(origin = nil)
        return false unless browser.started?

        page.ferrum.network.traffic.any? do |exchange|
          exchange.pending? && (origin.nil? || exchange.request&.url.to_s.start_with?(origin))
        end
      end

      def reset!
        return unless browser.started?

        browser.reset!(clear_local_storage: @options[:clear_local_storage],
                       clear_session_storage: @options[:clear_session_storage])
      end

      def quit
        browser.quit
      end

      def page
        browser.current_page
      end

      private

      def within_window(handle)
        original = browser.current_target_id
        browser.switch_to(handle)
        yield
      ensure
        browser.switch_to(original) if original && original != handle
      end

      def native_args(args)
        args.map do |arg|
          case arg
          when Capybara::Node::Element then arg.native
          when Array then native_args(arg)
          when Hash then arg.transform_values { |v| native_args([v]).first }
          else arg
          end
        end
      end
    end
  end
end
