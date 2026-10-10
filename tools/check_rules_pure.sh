#!/bin/sh
# Rules files must not touch global RNG, the scene tree, Input, time or Engine.
status=0
for f in scripts/card.gd scripts/card_library.gd scripts/ball_type.gd scripts/zone.gd scripts/zone_layout.gd \
         scripts/rally_resolver.gd scripts/match_state.gd scripts/ai_controller.gd \
         scripts/run_state.gd scripts/opponent_library.gd; do
	sed 's/#.*//' "$f" | grep -HnE --label="$f" \
		'(^|[^.A-Za-z_])(randi|randf|randi_range|randf_range|randfn|randomize|seed)\(|\.shuffle\(\)|get_tree\(|get_node\(|\bInput\.|\bTime\.|\bEngine\.|\bOS\.|\bDisplayServer\.' \
		&& status=1
done
exit $status
