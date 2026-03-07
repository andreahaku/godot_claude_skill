@tool
class_name EventBus
extends Node

## Centralized event bus for push notifications to WebSocket clients.
## Supports subscribing to event types: scene_changed, node_added, node_removed,
## script_error, game_started, game_stopped, file_changed

signal event_emitted(event_type: String, data: Dictionary)

var _subscriptions: Dictionary = {}  # peer_id -> Array[String] of event types

func subscribe(peer_id: int, event_types: Array) -> Dictionary:
	# Store subscriptions for this peer
	_subscriptions[peer_id] = event_types
	return {"subscribed": event_types, "peer_id": peer_id}

func unsubscribe(peer_id: int) -> Dictionary:
	_subscriptions.erase(peer_id)
	return {"unsubscribed": true}

func get_subscriptions(peer_id: int) -> Array:
	return _subscriptions.get(peer_id, [])

func get_all_subscribers() -> Dictionary:
	return _subscriptions.duplicate()

func emit_event(event_type: String, data: Dictionary) -> void:
	event_emitted.emit(event_type, data)

func remove_peer(peer_id: int) -> void:
	_subscriptions.erase(peer_id)

func get_subscribers_for_event(event_type: String) -> Array[int]:
	var peers: Array[int] = []
	for peer_id in _subscriptions:
		var types: Array = _subscriptions[peer_id]
		if event_type in types or "*" in types:
			peers.append(peer_id)
	return peers
