# frozen_string_literal: true

require "capybara/node/whitespace_normalizer"

module Capybara
  module Devtools
    class Node < Capybara::Driver::Node
      include Capybara::Node::WhitespaceNormalizer

      RAPID_SET_LENGTH = 30

      attr_reader :page, :frame, :token, :id

      def initialize(driver, page, frame, token, id, initial_cache = {}) # rubocop:disable Metrics/ParameterLists
        super(driver, self, initial_cache)
        @page = page
        @frame = frame
        @token = token
        @id = id
      end

      def call(function, *, await: false)
        page.call(function, token, id, *, frame: frame, await: await)
      end

      # Viewport point to interact with, after animations settled and the element was scrolled into view.
      def pointer(x, y, position, check, name)
        call("pointer", x, y, position, check, name, await: true)
      end

      # ---- finding ----

      def find_xpath(selector, **hints)
        page.find(:xpath, selector, self, hints)
      end

      def find_css(selector, **hints)
        page.find(:css, selector, self, hints)
      end

      # ---- reading ----

      def all_text
        normalize_spacing(call("allText").to_s)
      end

      def visible_text
        normalize_visible_spacing(call("visibleText").to_s)
      end

      def [](name)
        call("attribute", name.to_s)
      end
      alias attribute []

      def property(name)
        call("property", name.to_s)
      end

      def value
        call("value")
      end

      def style(styles)
        call("style", styles.map(&:to_s))
      end

      def tag_name
        @tag_name ||= initial_cache[:tag_name] || call("tagNameOf")
      end

      def visible?
        call("visible")
      end

      def obscured?
        call("obscured")
      end

      def checked?
        call("checked")
      end

      def selected?
        call("selected")
      end

      def disabled?
        call("disabled")
      end

      def readonly?
        !!self[:readOnly]
      end

      def multiple?
        !!self[:multiple]
      end

      def path
        call("path")
      end

      def rect
        call("rect")
      end

      def shadow_root
        ref = call("shadowRoot")
        ref && Node.new(driver, page, frame, ref["__cdToken"], ref["__cdNode"], tag_name: "ShadowRoot")
      end

      # ---- writing ----

      def set(value, **)
        if value.is_a?(Array) && !multiple?
          raise ArgumentError, "Value cannot be an Array when 'multiple' attribute is not present. Not a #{value.class}"
        end

        case tag_name
        when "input"
          set_input(value, **)
        when "textarea"
          set_text(value, **)
        else
          set_content_editable(value)
        end
      end

      def select_option
        call("selectOption", true)
      end

      def unselect_option
        call("selectOption", false)
      end

      def click(keys = [], **options)
        perform_click(:left, "click", keys, options)
      end

      def right_click(keys = [], **options)
        perform_click(:right, "right_click", keys, options)
      end

      def double_click(keys = [], **options)
        perform_click(:double, "double_click", keys, options)
      end

      def send_keys(*keys)
        keys = keys.reject { |key| key.nil? || key == "" }
        return if keys.empty?

        call("focus")
        type_keys(*keys)
      end
      alias send_key send_keys

      def hover
        x, y = pointer(nil, nil, nil, false, "hover")
        input.move(x, y)
      end

      def trigger(event)
        call("trigger", event.to_s)
      end

      def drag_to(other, html5: nil, delay: 0.05, drop_modifiers: [], **)
        drop_modifiers = Array(drop_modifiers).map { |m| normalize_modifier(m) }
        page.evaluate("#{Page::RUNTIME}.dragMousedownTracker()", frame: frame)
        x, y = pointer(nil, nil, nil, false, "drag")
        input.move(x, y)
        input.down
        html5 = !call("legacyDrag") if html5.nil?

        if html5
          page.run_script(JavaScript.html5_drag, [self, other, delay * 1000, drop_modifiers.map(&:to_s)],
                          async: true, wait: driver.session_options.default_max_wait_time)
          input.up
        else
          modifiers = input.modifiers(drop_modifiers)
          x2, y2 = other.pointer(nil, nil, nil, false, "drop")
          input.move(x2, y2, steps: 2)
          input.up(modifiers: modifiers)
        end
      end

      def drop(*args)
        if args[0].is_a?(String)
          ref = page.evaluate("#{Page::RUNTIME}.attachDropInput()", frame: frame)
          input = Node.new(driver, page, frame, ref["__cdToken"], ref["__cdNode"], tag_name: "input")
          input.set_file(args)
          call("dropFiles")
        else
          strings = args.flat_map { |arg| arg.map { |type, data| { "type" => type, "data" => data } } }
          call("dropStrings", strings)
        end
      end

      def scroll_by(x, y)
        driver.execute_script("arguments[0].scrollBy(arguments[1], arguments[2])", self, x, y)
      end

      def scroll_to(element, location, position = nil)
        if element.is_a?(Node)
          options = case location
                    when :top then "true"
                    when :bottom then "false"
                    when :center then "{behavior: 'instant', block: 'center'}"
                    else raise ArgumentError, "Invalid scroll_to location: #{location}"
                    end
          driver.execute_script("arguments[0].scrollIntoView(#{options})", element)
        elsif location.is_a?(Symbol)
          target = { top: "0", bottom: "arguments[0].scrollHeight",
                     center: "(arguments[0].scrollHeight - arguments[0].clientHeight)/2" }.fetch(location)
          driver.execute_script("arguments[0].scrollTo(0, #{target})", self)
        else
          driver.execute_script("arguments[0].scrollTo(arguments[1], arguments[2])", self, *position)
        end
        self
      end

      def set_file(value)
        files = Array(value).map { |path| File.expand_path(path.to_s) }
        page.ferrum.command("DOM.setFileInputFiles", files: files, objectId: page.object_id_of(self))
      end

      def ==(other)
        other.is_a?(Node) && other.token == token && other.id == id
      end

      def inspect
        %(#<#{self.class} tag="#{initial_cache[:tag_name]}" id=#{id}>)
      end

      private

      def set_input(value, **)
        case self[:type].to_s.downcase
        when "radio" then click
        when "checkbox" then click if value ^ checked?
        when "file" then set_file(value)
        when "date" then set_date(value)
        when "time" then set_time(value)
        when "datetime-local" then set_datetime_local(value)
        when "color", "range" then call("setValue", value.to_s)
        else set_text(value, **)
        end
      end

      def set_date(value)
        return set_text(value) if value.is_a?(String) || !value.respond_to?(:to_date)

        call("setValue", value.to_date.iso8601)
      end

      def set_time(value)
        return set_text(value) if value.is_a?(String) || !value.respond_to?(:to_time)

        call("setValue", value.to_time.strftime("%H:%M"))
      end

      def set_datetime_local(value)
        return set_text(value) if value.is_a?(String) || !value.respond_to?(:to_time)

        call("setValue", value.to_time.strftime("%Y-%m-%dT%H:%M"))
      end

      def set_text(value, clear: nil, rapid: nil, **_unused)
        value = value.to_s
        if value.empty? && clear.nil?
          call("clearValue")
        elsif clear == :backspace
          call("prepareText", false)
          backspaces = [:backspace] * self.value.to_s.length
          type_keys(:end, *backspaces, value)
        elsif clear.is_a?(Array)
          call("prepareText", false)
          type_keys(*clear, value)
        else
          call("prepareText", clear != :none)
          if rapid == true || (value.length > RAPID_SET_LENGTH && rapid != false)
            type_keys(value[0..3])
            insert_text(value[4...-3])
            type_keys(value[-3..])
          else
            type_keys(value)
          end
        end
      end

      # A line break in typed text is the Enter key, as a user would press it.
      def type_keys(*keys)
        expanded = keys.flat_map do |key|
          next [key] unless key.is_a?(String) && key.match?(/[\r\n]/)

          key.split(/(\r\n|\r|\n)/).reject(&:empty?).map { |part| part.match?(/\A[\r\n]+\z/) ? :enter : part }
        end
        input.type(*expanded) unless expanded.empty?
      end

      def insert_text(text)
        page.ferrum.command("Input.insertText", text: text)
      end

      def set_content_editable(value)
        return unless call("selectContents")

        type_keys(value.to_s)
      end

      def perform_click(mode, name, keys, options)
        x, y = options.values_at(:x, :y)
        position = options[:offset] == :center ? "center" : "top"
        check = x.nil? || y.nil?
        px, py = pointer(x, y, position, check, name)
        modifiers = input.modifiers(keys)
        button = mode == :right ? "right" : "left"
        delay = options[:delay].to_f
        input.move(px, py, await: false)
        input.down(button: button, modifiers: modifiers, await: delay.positive?)
        sleep(delay) if delay.positive?
        input.up(button: button, modifiers: modifiers)
        return unless mode == :double

        input.down(button: button, modifiers: modifiers, count: 2, await: false)
        input.up(button: button, modifiers: modifiers, count: 2)
      end

      def normalize_modifier(key)
        { control: :ctrl, command: :meta, cmd: :meta }.fetch(key.to_sym, key.to_sym)
      end

      def input
        page.input
      end
    end
  end
end
