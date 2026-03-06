@tool
class_name UndoHelper
extends RefCounted

## Wraps Godot's UndoRedo system for consistent undo/redo support.
## Every mutation should go through this helper so Ctrl+Z works for all AI operations.
##
## In Godot 4.6, EditorUndoRedoManager.add_do_method() uses vararg signature:
##   add_do_method(object: Object, method: StringName, arg1, arg2, ...)
## We use callv() to forward an array of arguments to this vararg method.

var _undo_redo: EditorUndoRedoManager


func setup(undo_redo: EditorUndoRedoManager) -> void:
	_undo_redo = undo_redo


func create_action(name: String, merge_mode: int = 0) -> void:
	_undo_redo.create_action(name, merge_mode)


func add_do_method(object: Object, method: StringName, args: Array = []) -> void:
	var call_args: Array = [object, method]
	call_args.append_array(args)
	_undo_redo.callv(&"add_do_method", call_args)


func add_undo_method(object: Object, method: StringName, args: Array = []) -> void:
	var call_args: Array = [object, method]
	call_args.append_array(args)
	_undo_redo.callv(&"add_undo_method", call_args)


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
