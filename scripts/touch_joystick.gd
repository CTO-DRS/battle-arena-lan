extends Control
## TouchJoystick — عصا تحكم افتراضية بسيطة تعمل باللمس (والفأرة عبر المحاكاة).
##
## ملاحظة تقنية: نعتمد حصراً على أحداث اللمس (InputEventScreenTouch/Drag)
## لأن المشروع يفعّل emulate_touch_from_mouse — فيعمل نفس المسار على الهاتف
## والكمبيوتر معاً دون ازدواجية.

signal moved(vec: Vector2)

const RADIUS := 80.0

var output := Vector2.ZERO

var _touch_index := -1
var _center := Vector2.ZERO


func _ready() -> void:
        custom_minimum_size = Vector2(240, 240)
        mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
        if event is InputEventScreenTouch:
                if event.pressed and _touch_index == -1:
                        _touch_index = event.index
                        _center = event.position
                        queue_redraw()
                elif not event.pressed and event.index == _touch_index:
                        _release()
        elif event is InputEventScreenDrag and event.index == _touch_index:
                var d: Vector2 = event.position - _center
                output = d.limit_length(RADIUS) / RADIUS
                moved.emit(output)
                queue_redraw()


func _release() -> void:
        _touch_index = -1
        output = Vector2.ZERO
        moved.emit(output)
        queue_redraw()


func _draw() -> void:
        # قاعدة العصا.
        draw_circle(Vector2(size.x * 0.5, size.y * 0.5), RADIUS + 18.0, Color(1, 1, 1, 0.05))
        draw_arc(Vector2(size.x * 0.5, size.y * 0.5), RADIUS + 18.0, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 2.0)
        # مقبض العصا يتبع الإصبع.
        var handle := Vector2(size.x * 0.5, size.y * 0.5)
        if _touch_index != -1 and output != Vector2.ZERO:
                handle += output * RADIUS
        draw_circle(handle, 34.0, Color(0.85, 0.55, 0.2, 0.55))
