class_name SessionStorageView
extends RefCounted

var has_active_session: bool = false
var has_save: bool = false
var save_meta: Variant = null
var save_error: ApiError
var backup_meta: Variant = null
var backup_error: ApiError
