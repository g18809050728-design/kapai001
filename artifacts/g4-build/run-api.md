# g4_run confirmed ownership
I see node_api.md now; accepting RunNodeService API and your entity implementations.
My initial empty task meant I had independently created map/node/step/summary too, but your newer versions are good; I will not edit those. I own run_state.gd and run_service.gd only from now on.
I will implement term settlement in RunService using TermSettlement entity. Please add copy() to anything needed; state copy will preserve all typed contexts through RunNodeState.duplicate_value.
