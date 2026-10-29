extends SceneTree
# Exercises the systems the smoke run doesn't reach: every random event, saves, building, terrain, design.
func _initialize():
	await process_frame
	var sim = root.get_node("Sim")
	for sc in ["fresh", "city", "seaside", "oakmere", "frost", "estate", "champ", "sandbox"]:
		sim.startScenario(sc, "hard", "T")
		for i in 300: sim.tick(0.1)
		print(sc, ": money ", sim.S.money, " holes ", sim.courseHoles(), " objs ", sim.objs().size(), " medal ", sim.medalNow(sim.scenOf(sc)) if sc != "sandbox" else 0)
	sim.startScenario("estate", "normal", "Events GC")
	sim.S.day = 10
	for k in sim.RANDOM_EVENTS:
		sim.fireRandomEvent(k)
		while sim.evQueue.size():
			var ev = sim.evQueue.pop_front()
			sim.showEventCard(ev); sim.chooseEventOption(randi() % ev.options.size())
		for i in 50: sim.tick(0.1)
		sim.facList(); for it in sim.facList(): sim.facStatus(it.key)
		for m in sim.activeMods(): sim.modFx(m)
	print("events ok, mods ", sim.S.mods.size())
	# saving and loading
	sim.saveToSlot("3")
	var money = sim.S.money
	sim.startScenario("fresh", "easy", "Other")
	print("load ", sim.loadSlot("3"), " money same ", is_equal_approx(sim.S.money, money), " name ", sim.clubName())
	for i in 600: sim.tick(0.1)
	# terrain brushes
	sim.startScenario("sandbox", "normal", "Terra")
	for tool in sim.TERRA.keys():
		for k in 5: sim.terraBrush(tool, 600 + k * 20, 600)
		print("terra ", tool, " -> ", sim.endTerraStroke())
	sim.waterField()
	print("water bodies ", sim.WF.bodies.size())
	# designer
	sim.startScenario("fresh", "normal", "Design")
	sim.S.money = 1e6
	for t in sim.OBJ.keys():
		var placed := false
		for ty in range(2, 70, 3):
			for tx in range(2, 100, 3):
				if sim.canPlace(t, tx, ty).ok:
					sim.placeObj(t, tx, ty); placed = true; break
			if placed: break
		print("place ", t, " ", placed)
	for n in sim.needsPath():
		var r = sim.suggestFor(n)
		print("path for ", n.label, ": ", r.get("fail", "%d tiles" % r.get("tiles", []).size()))
		if r.has("tiles"): sim.buildPathTiles(r.tiles, n.label)
	sim.enterDesign()
	print("designing ", sim.designing)
	sim.exitDesign()
	for i in 3000: sim.tick(0.1)
	print("visitors ", sim.visitors.size(), " rounds ", sim.S.get("rounds", 0))
	quit()
