# frozen_string_literal: true

module Capybara
  module Devtools
    # Mouse and keyboard events of one tab. An event followed by another one is sent without
    # waiting for its response: Chrome handles the events of a session in order, so the response
    # of the last one means all of them were handled.
    class Input
      BUTTON_MASKS = { "none" => 0, "left" => 1, "right" => 2, "middle" => 4 }.freeze

      def initialize(ferrum)
        @ferrum = ferrum
        @x = 0
        @y = 0
        @buttons = 0
      end

      def move(x, y, steps: 1, await: true)
        from_x = @x
        from_y = @y
        @x = x
        @y = y
        steps.times do |i|
          fraction = (i + 1) / steps.to_f
          step_x = from_x + ((x - from_x) * fraction)
          step_y = from_y + ((y - from_y) * fraction)
          dispatch("Input.dispatchMouseEvent", await: await && i == steps - 1, type: "mouseMoved", x: step_x, y: step_y,
                                               buttons: @buttons)
        end
      end

      def down(button: "left", count: 1, modifiers: 0, await: true)
        @buttons |= BUTTON_MASKS.fetch(button)
        mouse_event("mousePressed", button, count, modifiers, await)
      end

      def up(button: "left", count: 1, modifiers: 0, await: true)
        @buttons &= ~BUTTON_MASKS.fetch(button)
        mouse_event("mouseReleased", button, count, modifiers, await)
      end

      def type(*keys)
        events = @ferrum.keyboard.send(:normalize_keys, keys).flat_map do |key|
          [[key[:text] ? "keyDown" : "rawKeyDown", key], ["keyUp", key]]
        end
        events.each_with_index do |(type, key), index|
          dispatch("Input.dispatchKeyEvent", await: index == events.size - 1, type: type, **key)
        end
      end

      def modifiers(keys)
        @ferrum.keyboard.modifiers(keys)
      end

      private

      def mouse_event(type, button, count, modifiers, await)
        dispatch("Input.dispatchMouseEvent", await: await, type: type, x: @x, y: @y, button: button,
                                             buttons: @buttons, clickCount: count, modifiers: modifiers)
      end

      def dispatch(method, await:, **params)
        @ferrum.command(method, async: !await, **params)
      end
    end
  end
end
