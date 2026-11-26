extends "../rock_bank_recipe.gd"
## Test only: the synthetic world uses artificial crossing-water cells.
## All production checks except source-file identity are exercised unchanged.
func _canonical_source_ok(_world: Node) -> bool:
	return true
