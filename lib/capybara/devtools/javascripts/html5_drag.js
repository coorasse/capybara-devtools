// HTML5 drag and drop emulation, taken from Capybara's Selenium driver (MIT) so both drivers behave the same.
function rectCenter(rect){
  return new DOMPoint(
    (rect.left + rect.right)/2,
    (rect.top + rect.bottom)/2
  );
}

function pointOnRect(pt, rect) {
	var rectPt = rectCenter(rect);
	var slope = (rectPt.y - pt.y) / (rectPt.x - pt.x);

	if (pt.x <= rectPt.x) { // left side
		var minXy = slope * (rect.left - pt.x) + pt.y;
		if (rect.top <= minXy && minXy <= rect.bottom)
      return new DOMPoint(rect.left, minXy);
	}

	if (pt.x >= rectPt.x) { // right side
		var maxXy = slope * (rect.right - pt.x) + pt.y;
		if (rect.top <= maxXy && maxXy <= rect.bottom)
      return new DOMPoint(rect.right, maxXy);
	}

	if (pt.y <= rectPt.y) { // top side
		var minYx = (rectPt.top - pt.y) / slope + pt.x;
		if (rect.left <= minYx && minYx <= rect.right)
      return new DOMPoint(minYx, rect.top);
	}

	if (pt.y >= rectPt.y) { // bottom side
		var maxYx = (rect.bottom - pt.y) / slope + pt.x;
		if (rect.left <= maxYx && maxYx <= rect.right)
      return new DOMPoint(maxYx, rect.bottom);
	}

  return new DOMPoint(pt.x,pt.y);
}

function dispatchOnElement(pt, event) {
  var el = document.elementFromPoint(pt.x, pt.y);
  if (!el || !target.contains(el)) el = target;
  el.dispatchEvent(event);
}

function dragEnterTarget() {
  target.scrollIntoView({behavior: 'instant', block: 'center', inline: 'center'});
  var targetRect = target.getBoundingClientRect();
  var sourceCenter = rectCenter(source.getBoundingClientRect());

  for (var i = 0; i < drop_modifier_keys.length; i++) {
    key = drop_modifier_keys[i];
    if (key == "control"){
      key = "ctrl"
    }
    opts[key + 'Key'] = true;
  }

  var entryPoint = pointOnRect(sourceCenter, targetRect)
  var enterOpts = Object.assign({clientX: entryPoint.x, clientY: entryPoint.y}, opts);
  var dragEnterEvent = new DragEvent('dragenter', enterOpts);
  dispatchOnElement(entryPoint, dragEnterEvent);

  // fire 2 dragover events to simulate dragging with a direction
  var dragOverOpts = Object.assign({clientX: entryPoint.x, clientY: entryPoint.y}, opts);
  var dragOverEvent = new DragEvent('dragover', dragOverOpts);
  dispatchOnElement(entryPoint, dragOverEvent);
  window.setTimeout(dragOnTarget, step_delay);
}

function dragOnTarget() {
  var targetCenter = rectCenter(target.getBoundingClientRect());
  var dragOverOpts = Object.assign({clientX: targetCenter.x, clientY: targetCenter.y}, opts);
  var dragOverEvent = new DragEvent('dragover', dragOverOpts);
  dispatchOnElement(targetCenter, dragOverEvent);
  window.setTimeout(dragLeave, step_delay, dragOverEvent.defaultPrevented, dragOverOpts);
}

function dragLeave(drop, dragOverOpts) {
  var dragLeaveOptions = Object.assign({}, opts, dragOverOpts);
  var pt = {x: dragOverOpts.clientX, y: dragOverOpts.clientY};
  if (drop) {
    var dropEvent = new DragEvent('drop', dragLeaveOptions);
    dispatchOnElement(pt, dropEvent);
  } else {
    var dragLeaveEvent = new DragEvent('dragleave', dragLeaveOptions);
    dispatchOnElement(pt, dragLeaveEvent);
  }
  var dragEndEvent = new DragEvent('dragend', dragLeaveOptions);
  source.dispatchEvent(dragEndEvent);
  callback.call(true);
}

var source = arguments[0],
    target = arguments[1],
    step_delay = arguments[2],
    drop_modifier_keys = arguments[3],
    callback = arguments[4];

var dt = new DataTransfer();
var opts = { cancelable: true, bubbles: true, dataTransfer: dt };

if (!source.draggable) {
  var child = source.querySelector('[draggable="true"]');
  if (child) {
    source = child;
  } else {
    while (source && !source.draggable) {
      source = source.parentElement;
    }
  }
}

if (source.tagName == 'A'){
  dt.setData('text/uri-list', source.href);
  dt.setData('text', source.href);
}
if (source.tagName == 'IMG'){
  dt.setData('text/uri-list', source.src);
  dt.setData('text', source.src);
}

var srcCenter = rectCenter(source.getBoundingClientRect());
var dragStartOpts = Object.assign({clientX: srcCenter.x, clientY: srcCenter.y}, opts);
var dragEvent = new DragEvent('dragstart', dragStartOpts);
source.dispatchEvent(dragEvent);

// Yield once to the event loop so libraries that defer work after
// dragstart (e.g. react-dnd's publishDragSource via setTimeout(0))
// can complete before we dispatch dragenter.
window.setTimeout(function() {
  window.setTimeout(dragEnterTarget, step_delay);
}, 0);
