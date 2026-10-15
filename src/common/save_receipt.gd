class_name SaveReceipt
extends RefCounted

var slot: StringName
var revision: int = 0
var checksum: String
var written_at: String
var saved_at: String:
	get:
		return written_at
	set(value):
		written_at = value
