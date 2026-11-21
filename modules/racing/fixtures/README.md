# Independent racing fixtures

These are **local tests**, not the World Agent's canonical `data/world/road_graph_v1.json`.

- Town: four directed lane centerlines forming an approximately 0.8 km closed loop, four checkpoints, 3 laps.
- Ridge: four connected uphill directed lanes, four checkpoints, a one-lap sprint.
- Coordinates are [x, y, z] in Godot meters. Grades are deliberately gentle; road surfaces are data only.
- Use the World Agent's exported graph for production; create new event lane routes/checkpoints against those real lane IDs. Do not replace these fixture IDs blindly.
