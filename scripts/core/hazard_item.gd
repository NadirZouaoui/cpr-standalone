class_name HazardItem
extends Resource
## One line on the hazard assessment list.
##
## Data, not code, for the same reason KitItem is: **the client did not write
## any of this and is going to want to rewrite all of it.** Handing them a
## resource they can correct without a rebuild is the whole point of the file
## existing.
##
## `is_real` is the answer key. Everything else is presentation, teaching text,
## or the provenance flags that keep an invented line from quietly becoming
## house truth.

## Stable identifier. Grading, logging and the headless checks key off this,
## never off the wording - the wording is expected to change.
@export var id: StringName = &""

## The line as the trainee reads it on the panel.
@export_multiline var label: String = ""

## THE ANSWER KEY. True when this is genuinely a hazard in this room at this
## moment; false when it is a distractor that should be left un-ticked.
@export var is_real: bool = false

## Why, revealed in the debrief. This is where the teaching happens, so it
## should say what the hazard does to you, not restate the label.
@export_multiline var rationale: String = ""

## Set on any entry that has NOT been confirmed against the room, or that is
## known to describe something the simulation does not yet model.
##
## Nothing in the runtime behaves differently: the flag exists so the handover
## report and `HazardList.review_notes()` can list exactly which lines need the
## client's or Nadir's eye, rather than that knowledge living only in a ledger
## nobody reads twice.
@export var needs_review: bool = false

## What specifically is unresolved about this entry. Free text, printed in the
## review listing next to the label.
@export_multiline var review_note: String = ""
