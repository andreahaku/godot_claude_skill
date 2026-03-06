@tool
class_name UndoHelper
extends RefCounted

## Wraps Godot's UndoRedo system for consistent undo/redo support.
## Every mutation should go through this helper so Ctrl+Z works for all AI operations.
## Uses EditorUndoRedoManager API for Godot 4.x
##
## In Godot 4.6, EditorUndoRedoManager.add_do_method() signature requires
## decomposing Callables into (object, method) + bound args.

var _undo_redo: EditorUndoRedoManager


func setup(undo_redo: EditorUndoRedoManager) -> void:
	_undo_redo = undo_redo


func create_action(name: String, merge_mode: int = 0) -> void:
	_undo_redo.create_action(name, merge_mode)


func add_do_method(callable: Callable) -> void:
	_call_method(&"add_do_method", callable)


func add_undo_method(callable: Callable) -> void:
	_call_method(&"add_undo_method", callable)


func _call_method(fn: StringName, callable: Callable) -> void:
	var obj = callable.get_object()
	var method = callable.get_method()
	var args = callable.get_bound_arguments()
	# Build the full argument array: [object, method, ...bound_args]
	var call_args: Array = [obj, method]
	call_args.append_array(args)
	_undo_redo.callv(fn, call_args)


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
