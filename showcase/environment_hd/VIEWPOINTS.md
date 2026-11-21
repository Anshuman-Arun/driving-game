# Six fixed Needle Pass camera compositions — render proof pending

Authoritative coordinates and FOV are in data/camera_shots_v2.json.
Both Godot and Blender read this same file. World coordinates are Godot XYZ;
Blender uses (x,-z,y). These are hand-set stations, not generated offsets.
A source-data terrain ray sanity check is not an actual rendered composition.

| View | Eye XYZ | Aim XYZ | Vertical FOV | Intention |
|---|---|---|---:|---|
| 1 | (-646,99,-471) | (-628,103,-565) | 50° | Road approach / forest leading line |
| 2 | (-641,100.5,-552) | (-623,102.5,-580) | 43° | Asphalt, road paint and shoulder |
| 3 | (-578,108.5,-616) | (-582,108.5,-642) | 56° | Close firs and forest parallax |
| 4 | (-513,116,-681) | (-520,113,-701) | 47° | Canonical rock slope and verge |
| 5 | (-385,154,-785) | (-580,119,-660) | 41° | Elevated reverse ridge vista |
| 6 | (-378,134,-809) | (-342,130,-807) | 49° | Crest backlight and reflections |

Standalone Godot keys 1–6 select the shots; integrated art disables the
comparison camera and UI. All six compositions remain VISUALLY UNVERIFIED
until actual raw 1600×900 Blender and Godot output is reviewed. Follow
LOCAL_RENDER_HANDOFF.md, not procedurally generated screenshots.
