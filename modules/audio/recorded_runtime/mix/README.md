# Aster Valley Recorded Audio Mix Subsystem (Track A)

This subsystem manages the canonical Godot `AudioBusLayout`, dynamic bus DSP processing, and camera-aware interior/exterior mix automation for Aster Valley.

## Files Created
- `bus_layout_builder.gd`: Programmatic builder (`AsterAudioBusBuilder`) to configure `AudioServer` or export `AudioBusLayout` resources.
- `camera_mix_controller.gd`: Smooth acoustic manager (`AsterCameraMixController`) transitioning between chase camera clarity and cockpit cabin muffling with 150-300ms smoothing.
- `aster_bus_layout.tres`: Pre-baked Godot AudioBusLayout with direct `Master` sends.
- `aster_bus_layout_sfx.tres`: Alternative AudioBusLayout with `SFX` submix routing for menu settings sliders.
- `tests/test_mix_subsystem.gd`: Automated test suite with 61 checks verifying all buses, gains, effects, serialization, and smoothing transitions.

---

## Bus Architecture & Calibrated Gains

| Bus Name | Default Send | SFX Send Mode | Start Gain | DSP Effects |
| :--- | :--- | :--- | :--- | :--- |
| **Master** | *(output)* | *(output)* | `0.0 dB` | **Gentle Compressor**: Threshold `-16 dB`, Ratio `2:1`, Attack `15ms` (`15000 us`), Release `120ms`.<br>**Limiter**: Ceiling `-1.0 dB`. |
| **SFX** | `Master` | `Master` | `0.0 dB` | Intermediate control bus for pause/settings UI sliders. |
| **Engine_Exhaust** | `Master` | `SFX` | `-6.0 dB` | Dynamic `AudioEffectLowPassFilter` for cockpit muffling (`20500 Hz` -> `1800 Hz`). |
| **Engine_Intake** | `Master` | `SFX` | `-12.0 dB` | Clean induction roar. Emphasized in cockpit to `-6.0 dB` (`+6 dB` boost). |
| **Exhaust_Reflection** | `Master` | `SFX` | `-18.0 dB` | **Wet-only Reflection Delay**: `dry = 0.0`, initial tap delay `40ms` (range `15-120ms`), `tap1_active = true`.<br>Acoustic absorption lowpass filter (`12000 Hz`). |
| **Tires** | `Master` | `SFX` | `-10.0 dB` | `AudioEffectHighPassFilter` (`120 Hz`) to clear rumble.<br>Dynamic `AudioEffectLowPassFilter` for cockpit muffling. |
| **Wind_Chassis** | `Master` | `SFX` | `-14.0 dB` | `AudioEffectHighPassFilter` (`80 Hz`) to clear subsonic rumble.<br>`AudioEffectEQ6` aerodynamic presence shaping.<br>Dynamic `AudioEffectLowPassFilter` for cockpit muffling. |
| **Ambience** | `Master` | `Master` | `-20.0 dB` | Dynamic `AudioEffectLowPassFilter` for cockpit muffling. |
| **Music** | `Master` | `Master` | `-18.0 dB` | Clean music pass-through. |
| **UI** | `Master` | `SFX` | `-12.0 dB` | Crisp feedback clicks and notifications. |

---

## Camera Mix Controller (`AsterCameraMixController`)

### Transition Smoothing
Transitions between exterior (chase) and interior (cockpit) are smoothed exponentially with time constant `smoothing_time = 0.20s` (200ms, adjustable within the 150-300ms range).

### Acoustic Modulation
- **Chase View (`weight = 0.0`)**: Full exterior clarity. Lowpass filters are wide open (`20500 Hz`). Engine exhaust at nominal `-6.0 dB`, intake at nominal `-12.0 dB`.
- **Cockpit View (`weight = 1.0`)**: Cabin muffling. Exterior lowpass filters close down to `~1800 Hz`. Exterior buses attenuated by `-4.0 dB`. Engine intake boosted by `+6.0 dB` (`-12 dB` -> `-6 dB`), emphasizing driver cabin throttle induction.

### Usage
```gdscript
# Attach controller to car or audio hierarchy
var mix_ctrl := AsterCameraMixController.new()
add_child(mix_ctrl)
mix_ctrl.bind_vehicle(my_vehicle) # Automatically detects CameraMounts/Cockpit marker

# Or manually trigger view switch
mix_ctrl.set_cockpit_view(true)  # Smooth transition to cockpit
mix_ctrl.set_cockpit_view(false) # Smooth transition to chase
```
