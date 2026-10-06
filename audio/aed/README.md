# AED voice lines

Ten mono files, dropped in here with these exact basenames. `.ogg` is preferred;
`.wav` and `.mp3` are also picked up (see `AUDIO_EXTENSIONS` in
`scripts/cpr/aed_voice.gd`). No code change is needed once they exist — a line
with no file simply holds its slot silently for 2.2 s and logs a warning naming
the wording it wanted.

Delivery: flat, unhurried, generic — no manufacturer names or branding.

| File | Line |
|---|---|
| `aed_unit_on` | "Unit ready. Stay calm and follow the spoken instructions." |
| `aed_attach_pads` | "Attach the pads to the patient's bare chest." |
| `aed_attach_second_pad` | "Attach the second pad." |
| `aed_pads_attached` | "Pads attached." |
| `aed_analysing` | "Analysing heart rhythm. Do not touch the patient." |
| `aed_shock_advised` | "Shock advised." |
| `aed_charging` | "Charging." |
| `aed_stand_clear` | "Stand clear. Press the flashing button to deliver the shock." |
| `aed_shock_delivered` | "Shock delivered." |
| `aed_resume_cpr` | "Begin CPR. Continue chest compressions." |

Still outstanding elsewhere (CPR_CONTRACT.md §9 seam 4): the metronome sample at
110/min and the negative tone for the breathing-check result.
