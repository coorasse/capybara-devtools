// Runtime injected into every document by the capybara-devtools driver.
// Every Capybara operation is one Runtime.evaluate call into this object.
// Elements are referenced by a per-document token plus a registry id, so a
// reference from a previous document is detected as stale instead of hitting
// the wrong element.
//
// isDisplayed is Selenium's isDisplayed atom (Apache 2.0), the same one the
// Capybara Selenium driver uses, so visibility semantics are identical.
(function () {
  if (window.__capybaraDevtools) return;

  const isDisplayed = __IS_DISPLAYED_ATOM__;

  class StaleNodeError extends Error { constructor(m) { super(m); this.name = "StaleNodeError"; } }
  class InvalidSelectorError extends Error { constructor(m) { super(m); this.name = "InvalidSelectorError"; } }
  class MouseEventFailedError extends Error { constructor(m) { super(m); this.name = "MouseEventFailedError"; } }
  class UnselectNotAllowedError extends Error { constructor(m) { super(m); this.name = "UnselectNotAllowedError"; } }

  const MOUSE_EVENTS = ["click", "dblclick", "mousedown", "mouseenter", "mouseleave", "mousemove", "mouseover", "mouseout", "mouseup", "contextmenu"];
  const FOCUS_EVENTS = ["blur", "focus", "focusin", "focusout"];

  const cd = {
    token: Math.random().toString(36).slice(2) + Date.now().toString(36),
    nodes: [null],

    register(node) {
      if (node.__cdId === undefined || this.nodes[node.__cdId] !== node) {
        node.__cdId = this.nodes.length;
        this.nodes.push(node);
      }
      return node.__cdId;
    },

    node(token, id) {
      if (token !== this.token) throw new StaleNodeError("the document has changed");
      const node = this.nodes[id];
      if (!node || !node.isConnected) throw new StaleNodeError("the element is no longer attached to the document");
      return node;
    },

    ref(node) {
      return { __cdNode: this.register(node), __cdToken: this.token, __cdTag: this.tagName(node) };
    },

    tagName(node) {
      if (node instanceof ShadowRoot) return "ShadowRoot";
      return node.tagName ? node.tagName.toLowerCase() : null;
    },

    // ---- finding -------------------------------------------------------

    find(token, method, selector, withinId, hints) {
      const within = withinId == null ? document : this.node(token, withinId);
      let results;
      try {
        if (method === "xpath") {
          const xpath = document.evaluate(selector, within, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
          results = [];
          for (let i = 0; i < xpath.snapshotLength; i++) results.push(xpath.snapshotItem(i));
        } else {
          results = Array.from(within.querySelectorAll(selector));
        }
      } catch (error) {
        if (error instanceof DOMException) throw new InvalidSelectorError(error.message);
        throw error;
      }

      if (hints.texts && hints.texts.length) {
        const texts = hints.texts.map(t => t.toLowerCase());
        results = results.filter(el => {
          const content = el.textContent.toLowerCase();
          return texts.every(t => content.indexOf(t) !== -1);
        });
      }

      const nodes = results.map(el => {
        const out = { id: this.register(el), tag: this.tagName(el) };
        if (hints.visible) out.visible = this.isVisible(el);
        if (hints.position) out.position = el.getBoundingClientRect().toJSON();
        if (hints.styles) out.style = this.computedStyles(el, hints.styles);
        return out;
      });
      return { token: this.token, nodes };
    },

    // ---- reading -------------------------------------------------------

    isVisible(node) {
      if (node instanceof ShadowRoot) node = node.host;
      if (node.nodeType !== Node.ELEMENT_NODE) return false;
      return !!isDisplayed(node, false);
    },

    visible(token, id) { return this.isVisible(this.node(token, id)); },

    visibleText(token, id) {
      const node = this.node(token, id);
      if (!this.isVisible(node)) return "";
      if (node instanceof ShadowRoot) {
        return Array.from(node.children).map(c => this.isVisible(c) ? c.innerText : "").filter(t => t).join(" ");
      }
      if (node.nodeName === "TEXTAREA" || node instanceof SVGElement) return node.textContent;
      return node.innerText;
    },

    allText(token, id) { return this.node(token, id).textContent; },

    attribute(token, id, name) {
      const el = this.node(token, id);
      const tag = this.tagName(el);
      if ((tag === "img" && name === "src") || (tag === "a" && name === "href")) {
        return el.hasAttribute(name) ? el[name] : null;
      }
      let value = el[name];
      if (value === undefined || value === null || typeof value === "object" || typeof value === "function") {
        value = el.getAttribute ? el.getAttribute(name) : null;
      }
      return value === undefined ? null : value;
    },

    property(token, id, name) {
      const value = this.node(token, id)[name];
      return value === undefined ? null : this.serialize(value);
    },

    value(token, id) {
      const el = this.node(token, id);
      if (el.tagName === "SELECT" && el.multiple) {
        return Array.from(el.options).filter(o => o.selected).map(o => o.value);
      }
      return el.value === undefined ? null : el.value;
    },

    computedStyles(el, names) {
      const styles = window.getComputedStyle(el);
      const out = {};
      names.forEach(name => { out[name] = styles.getPropertyValue(name); });
      return out;
    },

    style(token, id, names) { return this.computedStyles(this.node(token, id), names); },

    checked(token, id) { return !!this.node(token, id).checked; },
    selected(token, id) { return !!this.node(token, id).selected; },

    disabled(token, id) {
      const el = this.node(token, id);
      return !!(el.matches && el.matches(":disabled, select:disabled *"));
    },

    rect(token, id) { return this.node(token, id).getBoundingClientRect().toJSON(); },

    path(token, id) {
      let node = this.node(token, id);
      if (node.getRootNode && node.getRootNode() instanceof ShadowRoot) return "(: Shadow DOM element - no XPath :)";
      const parts = [];
      while (node && node !== document) {
        let pos = 0;
        let sibling = node;
        while (sibling) {
          if (sibling.nodeType === Node.ELEMENT_NODE && sibling.nodeName === node.nodeName) pos += 1;
          sibling = sibling.previousSibling;
        }
        parts.unshift(`${node.nodeName.toUpperCase()}[${pos}]`);
        node = node.parentNode;
      }
      return "/" + parts.join("/");
    },

    obscured(token, id) {
      let node = this.node(token, id);
      let win = window;
      let rect = node.getBoundingClientRect();
      let px = rect.left + rect.width / 2;
      let py = rect.top + rect.height / 2;
      while (win) {
        const topNode = win.document.elementFromPoint(px, py);
        if (node !== topNode && !node.contains(topNode)) return true;
        node = win.frameElement;
        if (!node) return false;
        rect = node.getBoundingClientRect();
        px = rect.left + px;
        py = rect.top + py;
        win = win.parent;
      }
      return false;
    },

    shadowRoot(token, id) {
      const root = this.node(token, id).shadowRoot;
      return root ? this.ref(root) : null;
    },

    activeElement() {
      const el = document.activeElement;
      return el ? this.ref(el) : null;
    },

    // ---- pointer -------------------------------------------------------

    frameOffset() {
      let win = window;
      const offset = { top: 0, left: 0 };
      while (win.frameElement) {
        const rect = win.frameElement.getClientRects()[0];
        const style = win.getComputedStyle(win.frameElement);
        win = win.parent;
        offset.top += rect.top + parseInt(style.getPropertyValue("padding-top"), 10);
        offset.left += rect.left + parseInt(style.getPropertyValue("padding-left"), 10);
      }
      return offset;
    },

    areaImage(node) {
      if (!node.tagName || node.tagName.toLowerCase() !== "area") return null;
      const map = node.parentNode;
      const name = map && map.getAttribute("name");
      return name ? document.querySelector(`img[usemap='#${name.toLowerCase()}']`) : null;
    },

    inViewport(node) {
      const rect = node.getBoundingClientRect();
      return rect.top >= 0 && rect.left >= 0 && rect.bottom <= window.innerHeight && rect.right <= window.innerWidth;
    },

    scrollIntoViewport(node) {
      if (!this.inViewport(node)) {
        node.scrollIntoView({ block: "center", inline: "center", behavior: "instant" });
      }
    },

    scrollIntoView(token, id, options) {
      this.node(token, id).scrollIntoView(options);
    },

    describeElement(el) {
      let selector = el.tagName.toLowerCase();
      if (el.id) selector += `#${el.id}`;
      el.classList.forEach(c => { selector += `.${c}`; });
      return selector;
    },

    // Scrolls the element into view and returns the viewport point (in top
    // window coordinates) to click. With `check` the point must hit the
    // element or a descendant, as a real user click would.
    async pointer(token, id, offsetX, offsetY, position, check, name) {
      const el = this.node(token, id);
      const target = this.areaImage(el) || el;
      await this.loaded();
      await this.settle(target);
      this.scrollIntoViewport(target);
      let point = this.pointOf(target, offsetX, offsetY, position);
      if (check) {
        let hit = this.hitTest(el, target, point);
        if (hit !== true) {
          // Scroll containers, sticky bars and overlays often cover an element near an edge; a user
          // would scroll it to the middle before clicking, so do the same once before giving up.
          target.scrollIntoView({ block: "center", inline: "center", behavior: "instant" });
          point = this.pointOf(target, offsetX, offsetY, position);
          hit = this.hitTest(el, target, point);
        }
        if (hit !== true) {
          const other = hit ? this.describeElement(hit) : "nothing";
          throw new MouseEventFailedError(`${name} at [${point[0]}, ${point[1]}] would hit ${other} instead of ${this.describeElement(el)}`);
        }
      }
      const offset = this.frameOffset();
      return [point[0] + offset.left, point[1] + offset.top];
    },

// The scripts that attach click handlers (deferred and module scripts) run after the document
// is parsed, so a page can be found and clicked before they ran. A user clicking right after the
// page appeared would wait for it to finish loading, briefly.
loaded() {
  if (document.readyState === "complete") return Promise.resolve();
  return new Promise(resolve => {
    const timer = setTimeout(resolve, 1000);
    window.addEventListener("load", () => { clearTimeout(timer); resolve(); }, { once: true });
  });
},

// Input events are hit-tested by the compositor, which can disagree with getBoundingClientRect
// while a CSS transition or animation moves the element (a fading-in modal, a collapsing
// section). Wait, briefly, for the animations affecting the element to finish, like a user
// waits for the UI to settle before clicking.
async settle(target) {
  if (!document.getAnimations) return;
  const deadline = performance.now() + 1000;
  while (performance.now() < deadline) {
    const running = document.getAnimations().filter(animation => this.animationAffects(animation, target));
    if (!running.length) return;
    await Promise.race([
      Promise.allSettled(running.map(animation => animation.finished)),
      new Promise(resolve => setTimeout(resolve, 50))
    ]);
  }
},

animationAffects(animation, target) {
  if (animation.playState !== "running") return false;
  const effect = animation.effect;
  if (!effect || !effect.target) return false;
  if (effect.getTiming().iterations === Infinity) return false;
  return effect.target === target || effect.target.contains(target);
},

    pointOf(target, offsetX, offsetY, position) {
      const rect = target.getBoundingClientRect();
      if (offsetX == null || offsetY == null) return [rect.left + rect.width / 2, rect.top + rect.height / 2];
      if (position === "center") return [rect.left + rect.width / 2 + offsetX, rect.top + rect.height / 2 + offsetY];
      return [rect.left + offsetX, rect.top + offsetY];
    },

    // true when the point hits the element (or a descendant), otherwise the element that was hit.
    hitTest(el, target, point) {
      const hit = el.getRootNode().elementFromPoint(point[0], point[1]);
      let current = hit;
      while (current) {
        if (current === el || current === target) return true;
        current = current.parentNode;
      }
      return hit;
    },

    // ---- writing -------------------------------------------------------

    focus(token, id) {
      const el = this.node(token, id);
      if (document.activeElement !== el) el.focus();
    },

    prepareText(token, id, selectAll) {
      const el = this.node(token, id);
      if (document.activeElement !== el) el.focus();
      if (!selectAll) return;
      if (typeof el.select === "function") {
        el.select();
      } else {
        const range = document.createRange();
        range.selectNodeContents(el);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
      }
    },

    nativeValueSetter(el) {
      const proto = el.tagName === "TEXTAREA" ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
      const descriptor = Object.getOwnPropertyDescriptor(proto, "value");
      return descriptor ? descriptor.set : null;
    },

    assignValue(el, value) {
      const setter = this.nativeValueSetter(el);
      if (setter) setter.call(el, value); else el.value = value;
    },

    clearValue(token, id) {
      const el = this.node(token, id);
      if (el.readOnly) return;
      if (document.activeElement !== el) el.focus();
      if (el.value === "") return;
      this.assignValue(el, "");
      el.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "deleteContentBackward" }));
      el.dispatchEvent(new Event("change", { bubbles: true }));
    },

    appendValue(token, id, text) {
      const el = this.node(token, id);
      let value = el.value + text;
      if (el.maxLength && el.maxLength !== -1) value = value.slice(0, el.maxLength);
      this.assignValue(el, value);
      el.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: text }));
    },

    // Used for date/time/color/range inputs, like Capybara's Selenium driver.
    setValue(token, id, value) {
      const el = this.node(token, id);
      if (el.readOnly) return;
      if (document.activeElement !== el) el.focus();
      if (el.value != value) {
        this.assignValue(el, value);
        el.dispatchEvent(new InputEvent("input", { bubbles: true }));
        el.dispatchEvent(new Event("change", { bubbles: true }));
      }
    },

    selectContents(token, id) {
      const el = this.node(token, id);
      if (!el.isContentEditable) return false;
      el.focus();
      const range = document.createRange();
      range.selectNodeContents(el);
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      return true;
    },

    selectOption(token, id, value) {
      const option = this.node(token, id);
      const select = option.closest("select");
      if (!select || this.disabledNode(option)) return;
      if (!value && !select.multiple) throw new UnselectNotAllowedError("Cannot unselect option from single select box.");
      if (option.selected === value) return;
      select.focus();
      option.selected = value;
      select.dispatchEvent(new InputEvent("input", { bubbles: true }));
      select.dispatchEvent(new Event("change", { bubbles: true }));
    },

    disabledNode(el) { return !!(el.matches && el.matches(":disabled, select:disabled *")); },

    trigger(token, id, name) {
      const node = this.node(token, id);
      let event;
      if (MOUSE_EVENTS.includes(name)) {
        event = new MouseEvent(name, { bubbles: true, cancelable: true, view: window });
      } else if (FOCUS_EVENTS.includes(name)) {
        event = new FocusEvent(name, { bubbles: true, cancelable: true });
      } else {
        event = new Event(name, { bubbles: true, cancelable: true });
      }
      node.dispatchEvent(event);
    },

    // ---- scripts -------------------------------------------------------

    deserialize(arg) {
      if (arg === null || typeof arg !== "object") return arg;
      if (Object.prototype.hasOwnProperty.call(arg, "__cdNode")) return this.node(arg.__cdToken, arg.__cdNode);
      if (Array.isArray(arg)) return arg.map(a => this.deserialize(a));
      const out = {};
      Object.keys(arg).forEach(k => { out[k] = this.deserialize(arg[k]); });
      return out;
    },

    serialize(value, seen = new Set()) {
      if (value === undefined || value === null) return null;
      const type = typeof value;
      if (type === "number") return Number.isFinite(value) ? value : null;
      if (type !== "object" && type !== "function") return value;
      if (type === "function") return null;
      if (value instanceof Node) return this.ref(value);
      if (value instanceof Date) return value.toJSON();
      if (seen.has(value)) return null;
      seen.add(value);
      let out;
      if (Array.isArray(value) || value instanceof NodeList || value instanceof HTMLCollection) {
        out = Array.from(value).map(v => this.serialize(v, seen));
      } else if (typeof value.toJSON === "function") {
        out = this.serialize(value.toJSON(), seen);
      } else {
        out = {};
        Object.keys(value).forEach(k => { out[k] = this.serialize(value[k], seen); });
      }
      seen.delete(value);
      return out;
    },

    run(fn, args) {
      return this.serialize(fn.apply(null, args.map(a => this.deserialize(a))));
    },

    runAsync(fn, args, wait) {
      const resolved = args.map(a => this.deserialize(a));
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error("timed out promise")), wait);
        resolved.push(result => { clearTimeout(timer); resolve(result); });
        try { fn.apply(null, resolved); } catch (e) { clearTimeout(timer); reject(e); }
      }).then(result => this.serialize(result));
    },

    // ---- drag and drop ----------------------------------------------

    dragMousedownTracker() {
      window.__cdMousedownPrevented = null;
      document.addEventListener("mousedown", ev => { window.__cdMousedownPrevented = ev.defaultPrevented; }, { once: true, passive: true });
    },

    legacyDrag(token, id) {
      if ([true, null].includes(window.__cdMousedownPrevented)) return true;
      const original = this.node(token, id);
      let el = original;
      do { if (el.draggable) return false; } while ((el = el.parentElement));
      if (original.querySelector && original.querySelector('[draggable="true"]')) return false;
      return true;
    },

    dropStrings(token, id, strings) {
      const target = this.node(token, id);
      const dt = new DataTransfer();
      strings.forEach(s => { dt.items.add(s.data, s.type); });
      target.dispatchEvent(new DragEvent("drop", { cancelable: true, bubbles: true, dataTransfer: dt }));
    },

    attachDropInput() {
      document.getElementById("__cd_drop_file")?.remove();
      const input = document.createElement("input");
      input.type = "file";
      input.id = "__cd_drop_file";
      input.multiple = true;
      document.body.appendChild(input);
      return this.ref(input);
    },

    dropFiles(token, id) {
      const target = this.node(token, id);
      const input = document.getElementById("__cd_drop_file");
      const dt = new DataTransfer();
      Array.from(input.files).forEach(f => dt.items.add(f));
      input.remove();
      target.dispatchEvent(new DragEvent("drop", { cancelable: true, bubbles: true, dataTransfer: dt }));
    }
  };

  window.__capybaraDevtools = cd;
})();
