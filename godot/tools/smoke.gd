extends SceneTree
# Runs the simulation headless for a while and prints a summary.
func _initialize():
	await process_frame
	var sim = root.get_node("Sim")
	sim.toast_shown.connect(func(k, t, x, i): print("  toast: ", k, " | ", t))
	var scen: String = OS.get_environment("SCEN") if OS.get_environment("SCEN") else "rescue"
	sim.startScenario(scen, "normal", "Smoke Test GC")
	var days := int(OS.get_environment("DAYS")) if OS.get_environment("DAYS") else 3
	var t0 := Time.get_ticks_msec()
	var steps := 0
	while sim.S.day < 1 + days + (sim.S.get("startDay", 1) - 1):
		sim.tick(0.1); sim.updateActors(steps * 0.1); steps += 1
		if steps % 900 == 0:
			sim.checkAchievements(); sim.hcpTick(3)
			print("day %d clock %.0f money %.0f visitors %d groups %d stars %d" % [sim.S.day, sim.S.clock, sim.S.money, sim.visitors.size(), sim.groups.size(), sim.stars()])
		if steps > 200000: break
	print("done: %d steps in %d ms · rounds %d buckets %d sales %d members %d rep %.0f" % [steps, Time.get_ticks_msec() - t0, sim.S.get("rounds",0), sim.S.get("buckets",0), sim.S.get("sales",0), sim.S.get("members",0), sim.S.get("rep",0)])
	quit()
