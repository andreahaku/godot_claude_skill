class_name UndoHelper

## Wraps Godot's UndoRedo system for consistent undo/redo support.
## Every mutation should go through this helper so Ctrl+Z works for all AI operations.

var _undo_redo: EditorUndoRedoManager

func _init(undo_redo: EditorUndoRedoManager):
	_undo_redo = undo_redo


func create_action(name: String, merge_mode: int = 0) -> void:
	_undo_redo.create_action(name, merge_mode)


func add_do_method(callable: Callable) -> void:
	_undo_redo.add_do_method(callable)


func add_undo_method(callable: Callable) -> void:
	_undo_redo.add_undo_method(callable)


func add_do_property(object: Object, property: StringName, value: Variant) -> void:
	_undo_redo.add_do_property(object, property, value)


func add_undo_property(object: Object, property: StringName, value: Variant) -> void:
	_undo_redo.add_undo_property(object, property, value)


func add_do_reference(object: Object) -> void:
	_undo_redo.add_do_reference(object)


func add_undo_reference(object: Object) -> void:
	_undo_redo.add_undo_reference(object)


func commit_action(execute: bool = true) -> void:
	_undo_redo.commit_action(execute)
