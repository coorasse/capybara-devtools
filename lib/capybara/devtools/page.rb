# frozen_string_literal: true

require "json"

module Capybara
  module Devtools
    # One browser tab. Wraps a Ferrum::Page but only uses it for process plumbing (CDP transport,
    # navigation, frames, screenshots). Every DOM operation goes through #call, a single
    # Runtime.evaluate into the injected runtime.
    class Page
      RUNTIME = "__capybaraDevtools"
      CONTEXT_ERRORS = [
        "Cannot find context with specified id",
        "Execution context was destroyed",
        "Inspected target navigated or closed",
        "Cannot find default execution context"
      ].freeze

      attr_reader :ferrum, :driver, :frame_stack, :modal_messages, :input

      def initialize(driver, ferrum)
        @driver = driver
        @ferrum = ferrum
        @input = Input.new(ferrum)
        @frame_stack = []
        @modal_expectations = []
        @modal_messages = []
        @modal_response = nil
        driver.logs.subscribe(ferrum)
        subscribe_dialogs
      end

      def target_id
        ferrum.target_id
      end

      def current_frame
        @frame_stack.last
      end

      # ---- runtime ------------------------------------------------------

      def call(function, *args, frame: current_frame, await: false)
        evaluate("#{RUNTIME}.#{function}(#{args.map do |arg|
          JSON.generate(arg)
        end.join(",")})", frame: frame, await: await)
      end

      def evaluate(expression, frame: current_frame, await: false, timeout: nil)
        injected = false
        begin
          params = { expression: expression, returnByValue: true, awaitPromise: await }
          params[:contextId] = frame.execution_id! if frame
          params[:timeout] = timeout if timeout
          response = ferrum.command("Runtime.evaluate", **params)
          raise_js_error(response["exceptionDetails"]) if response["exceptionDetails"]
          response.dig("result", "value")
        rescue JavaScriptError => e
          raise unless e.class_name == "ReferenceError" && e.message.include?(RUNTIME) && !injected

          injected = true
          inject_runtime(frame)
          retry
        rescue Ferrum::NodeNotFoundError, Ferrum::NoExecutionContextError => e
          raise ContextLost, e.message
        rescue Ferrum::BrowserError => e
          raise ContextLost, e.message if CONTEXT_ERRORS.any? { |msg| e.message.include?(msg) }

          raise
        end
      end

      # Returns the CDP objectId of a node, for the few commands that need one (file inputs, frames).
      def object_id_of(node)
        params = { expression: "#{RUNTIME}.node(#{node.token.to_json},#{node.id})", returnByValue: false }
        params[:contextId] = node.frame.execution_id! if node.frame
        response = ferrum.command("Runtime.evaluate", **params)
        raise_js_error(response["exceptionDetails"]) if response["exceptionDetails"]
        response.dig("result", "objectId")
      end

      def run_script(script, args, async: false, wait: nil)
        encoded = JSON.generate(args.map { |arg| encode_arg(arg) })
        if async
          wrapped = "#{RUNTIME}.runAsync(function(){ #{script}\n}, #{encoded}, #{(wait * 1000).to_i})"
          result = evaluate(wrapped, await: true, timeout: (wait * 1000).to_i + 1000)
        else
          result = evaluate("#{RUNTIME}.run(function(){ #{script}\n}, #{encoded})")
        end
        decode_result(result)
      end

      def find(method, selector, within, hints)
        js_hints = {
          visible: hints[:uses_visibility] || false,
          texts: hints[:texts] || [],
          position: hints[:position] || false,
          styles: hints[:styles].is_a?(Hash) ? hints[:styles].keys.map(&:to_s) : nil
        }
        frame = within ? within.frame : current_frame
        found = call("find", within&.token, method.to_s, selector.to_s, within&.id, js_hints, frame: frame)
        token = found["token"]
        found["nodes"].map do |result|
          cache = { tag_name: result["tag"] }
          cache[:visible] = result["visible"] if result.key?("visible")
          cache[:position] = result["position"] if result.key?("position")
          cache[:style] = result["style"] if result.key?("style")
          Node.new(driver, self, frame, token, result["id"], cache)
        end
      end

      # ---- frames -------------------------------------------------------

      def push_frame(node)
        description = ferrum.command("DOM.describeNode", objectId: object_id_of(node))["node"]
        frame_id = description["frameId"]
        raise ArgumentError, "the element is not a frame" unless frame_id

        @frame_stack.push(ferrum.frame_by(id: frame_id))
      end

      def pop_frame
        @frame_stack.pop
      end

      def top_frame
        @frame_stack.clear
      end

      # ---- modals -------------------------------------------------------

      def expect_modal(accept, response = nil)
        @modal_expectations.push(accept)
        @modal_response = response
      end

      def find_modal(text: nil, wait: nil)
        wait ||= driver.session_options.default_max_wait_time
        regexp = text.is_a?(Regexp) ? text : Regexp.new(Regexp.escape(text.to_s))
        timer = Capybara::Helpers.timer(expire_in: wait)
        loop do
          message = @modal_messages.shift
          return message if message&.match?(regexp)

          if timer.expired?
            not_found = "Unable to find modal dialog"
            not_found += " with #{text}" if text
            raise Capybara::ModalNotFound, not_found
          end
          sleep 0.01
        end
      end

      def reset_state
        @frame_stack.clear
        @modal_expectations.clear
        @modal_messages.clear
        @modal_response = nil
      end

      private

      def subscribe_dialogs
        ferrum.on("Page.javascriptDialogOpening") do |params|
          accept = @modal_expectations.pop
          if accept.nil?
            accept = true
          else
            @modal_messages << params["message"]
          end
          options = { accept: accept }
          response = @modal_response || params["defaultPrompt"]
          options[:promptText] = response if response && params["type"] == "prompt"
          ferrum.command("Page.handleJavaScriptDialog", **options)
        rescue Ferrum::Error
          nil
        end
      end

      def inject_runtime(frame)
        params = { expression: JavaScript.source, returnByValue: true }
        params[:contextId] = frame.execution_id! if frame
        ferrum.command("Runtime.evaluate", **params)
      end

      def raise_js_error(details)
        exception = details["exception"] || {}
        class_name = exception["className"]
        description = exception["description"] || details["text"] || "JavaScript error"
        message = description.lines.first.to_s.strip.sub(/\A#{Regexp.escape(class_name.to_s)}:\s*/, "")
        case class_name
        when "StaleNodeError" then raise ObsoleteNode, message
        when "InvalidSelectorError" then raise InvalidSelector, message
        when "MouseEventFailedError" then raise MouseEventFailed, message
        when "UnselectNotAllowedError" then raise Capybara::UnselectNotAllowed, message
        else
          raise ScriptTimeoutError.new(message, class_name) if message.include?("timed out promise")

          raise JavaScriptError.new(description, class_name)
        end
      end

      def encode_arg(arg)
        case arg
        when Node then { "__cdNode" => arg.id, "__cdToken" => arg.token }
        when Array then arg.map { |a| encode_arg(a) }
        when Hash then arg.transform_values { |v| encode_arg(v) }
        else arg
        end
      end

      def decode_result(value)
        case value
        when Hash
          if value.key?("__cdNode")
            Node.new(driver, self, current_frame, value["__cdToken"], value["__cdNode"], tag_name: value["__cdTag"])
          else
            value.transform_values { |v| decode_result(v) }
          end
        when Array then value.map { |v| decode_result(v) }
        else value
        end
      end
    end
  end
end
