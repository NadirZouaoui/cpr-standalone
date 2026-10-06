"""Regenerate the LVR & CPR client walkthrough PDF.

Updated revision of the original client handout. Changes in this revision:

  * the walkthrough now reflects the exact 26-step graded procedure
  * "How a run can fail" documents all THREE failure conditions (fatal
    violations, sub-80% score, and critical-step violations), with a
    pass/fail decision diagram
  * critical steps (*) are marked inline throughout every phase, with the
    ordering traps spelled out where they actually bite (notably: open the
    airway must come AFTER the 000 radio call)
  * new "Complete table of critical steps & ordering traps"
  * new "Debrief screen legend" covering every mark the debrief screen uses
  * controls table expanded (G, Tab, H, Esc/P)

Run:  python make_walkthrough.py
"""

import os

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfbase.pdfmetrics import registerFontFamily
from reportlab.platypus import (BaseDocTemplate, CondPageBreak, Frame, Image,
                                KeepTogether, PageTemplate, Paragraph, Spacer,
                                Table, TableStyle)

OUT = "/home/z/my-project/download/LVR_CPR_Walkthrough.pdf"
DIAGRAM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pass_tree.png")
TITLE = "Low Voltage Rescue & CPR Simulation"
SUB = ("Walkthrough - the correct sequence, critical step rules, and the "
       "mistakes it is built to catch.")

# Palette: the handout's established client palette, unchanged.
INK = colors.HexColor("#1a1a1a")
MUTED = colors.HexColor("#5a5a5a")
RULE = colors.HexColor("#c8c8c8")
BAND = colors.HexColor("#f2f2f2")
ACCENT = colors.HexColor("#125b71")
# Semantic warning colour (muted red, XS-tier use: asterisks, critical tags).
WARN = colors.HexColor("#9d2f23")

# DejaVuSans (registered TTF) carries the debrief-screen marks
# (check, arrows, cross) that the Helvetica base font does not have.
pdfmetrics.registerFont(TTFont(
    "DejaVuSans", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"))
registerFontFamily("DejaVuSans", normal="DejaVuSans", bold="DejaVuSans")

ss = getSampleStyleSheet()
body = ParagraphStyle("body", parent=ss["BodyText"], fontName="Helvetica",
                      fontSize=9, leading=12.5, textColor=INK, spaceAfter=6,
                      alignment=TA_LEFT)
small = ParagraphStyle("small", parent=body, fontSize=8.5, leading=11.5,
                       spaceAfter=0)
smallmuted = ParagraphStyle("smallmuted", parent=small, textColor=MUTED)
sub = ParagraphStyle("sub", parent=small, leftIndent=4 * mm, spaceBefore=1.5)
note = ParagraphStyle("note", parent=smallmuted, leftIndent=4 * mm,
                      spaceBefore=1.5)
warn = ParagraphStyle("warn", parent=small, leftIndent=4 * mm, spaceBefore=2.5,
                      textColor=WARN)
bold = ParagraphStyle("bold", parent=small, fontName="Helvetica-Bold")
h1 = ParagraphStyle("h1", parent=body, fontName="Helvetica-Bold", fontSize=17,
                    leading=21, spaceAfter=2, textColor=INK)
h2 = ParagraphStyle("h2", parent=body, fontName="Helvetica-Bold", fontSize=11.5,
                    leading=15, spaceBefore=13, spaceAfter=5, textColor=ACCENT)
h3 = ParagraphStyle("h3", parent=body, fontName="Helvetica-Bold", fontSize=9.5,
                    leading=12.5, spaceBefore=9, spaceAfter=3, textColor=INK)
lede = ParagraphStyle("lede", parent=body, fontSize=9.5, leading=13.5,
                      textColor=MUTED, spaceAfter=10)
symbol = ParagraphStyle("symbol", parent=small, fontName="DejaVuSans")

WARNMARK = '<font color="#9d2f23" size="7.5"><b>*  CRITICAL STEP</b></font>'


def crit(head):
    """Mark a step heading as a critical step."""
    return "%s  %s" % (head, WARNMARK)


def _page(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 7.5)
    canvas.setFillColor(MUTED)
    canvas.drawString(18 * mm, A4[1] - 12 * mm, TITLE + " - walkthrough")
    canvas.drawRightString(A4[0] - 18 * mm, 12 * mm, "Page %d" % doc.page)
    canvas.setStrokeColor(RULE)
    canvas.setLineWidth(0.4)
    canvas.line(18 * mm, A4[1] - 14 * mm, A4[0] - 18 * mm, A4[1] - 14 * mm)
    canvas.restoreState()


def numbered(rows):
    """The step list: a number, a heading and a line of detail.

    Each row is (head, detail) or (head, detail, [extra flowables]) where the
    extras render under the detail inside the same cell (sub-bullets, notes,
    critical warnings).
    """
    data = []
    for i, row in enumerate(rows, start=1):
        head, detail = row[0], row[1]
        cell = [Paragraph("<b>%s</b><br/>%s" % (head, detail), small)]
        if len(row) > 2:
            cell.extend(row[2])
        data.append([Paragraph(str(i), bold), cell])
    t = Table(data, colWidths=[9 * mm, 165 * mm], hAlign="CENTER")
    t.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LEFTPADDING", (0, 0), (0, -1), 0),
        ("TEXTCOLOR", (0, 0), (0, -1), ACCENT),
        ("LINEBELOW", (0, 0), (-1, -2), 0.3, RULE),
    ]))
    return t


def two_col(rows, head_left, head_right, widths=(58 * mm, 116 * mm)):
    data = [[Paragraph(head_left, bold), Paragraph(head_right, bold)]]
    for a, b in rows:
        data.append([Paragraph(a, small), Paragraph(b, small)])
    t = Table(data, colWidths=list(widths), hAlign="CENTER", repeatRows=1)
    t.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("BACKGROUND", (0, 0), (-1, 0), BAND),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LEFTPADDING", (0, 0), (-1, -1), 5),
        ("LINEBELOW", (0, 0), (-1, -2), 0.3, RULE),
        ("BOX", (0, 0), (-1, -1), 0.3, RULE),
    ]))
    return t


def three_col(headers, rows, widths):
    data = [[Paragraph("<b>%s</b>" % h, bold) for h in headers]]
    for r in rows:
        data.append([Paragraph(c, small) for c in r])
    t = Table(data, colWidths=list(widths), hAlign="CENTER", repeatRows=1)
    t.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("BACKGROUND", (0, 0), (-1, 0), BAND),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LEFTPADDING", (0, 0), (-1, -1), 5),
        ("LINEBELOW", (0, 0), (-1, -2), 0.3, RULE),
        ("BOX", (0, 0), (-1, -1), 0.3, RULE),
    ]))
    return t


def embed_diagram(path, max_width, max_height=280):
    """Embed an image scaled to fit, preserving aspect ratio."""
    from PIL import Image as PILImage
    pw, ph = PILImage.open(path).size
    ratio = min(max_width / pw, max_height / ph, 1.0)
    return Image(path, width=pw * ratio, height=ph * ratio)


def keep_if_fits(flowables, measure, avail_height=300):
    """KeepTogether the block only when its measured height allows it."""
    total = 0
    for f in flowables:
        w, h = f.wrap(174 * mm, A4[1])
        total += h
    if total <= avail_height:
        return [KeepTogether(flowables)]
    return list(flowables)


def build():
    doc = BaseDocTemplate(
        OUT, pagesize=A4, title=TITLE + " - walkthrough",
        author="Nadir Zouaoui", creator="ReportLab",
        subject=("Client walkthrough for the LVR & CPR training simulation: "
                 "sequence, pass rules and critical step order."),
        leftMargin=18 * mm, rightMargin=18 * mm,
        topMargin=20 * mm, bottomMargin=18 * mm)
    frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height,
                  id="f")
    doc.addPageTemplates([PageTemplate(id="p", frames=[frame], onPage=_page)])

    s = []
    s.append(Paragraph(TITLE, h1))
    s.append(Paragraph(SUB, lede))
    s.append(Paragraph(
        "The trainee is the safety observer on a live low-voltage job. They "
        "identify the rescue kit, assess the hazards, witness the shock, break "
        "contact with the insulated crook, get the casualty clear and the "
        "supply dead, then work the primary survey through to CPR, the AED and "
        "the recovery position. Every action is graded and reported in a "
        "debrief at the end. About 10 minutes for a full run.", body))

    # ------------------------------------------------------------------
    s.append(Paragraph("Controls", h2))
    s.append(two_col([
        ("W A S D", "Walk. Hold <b>Shift</b> to sprint."),
        ("Mouse", "Look. The crosshair in the centre of the screen is your "
                  "cursor throughout - there is no free mouse pointer during "
                  "world exploration."),
        ("Left Mouse", "Interact. Pick up items, examine boards, place tools, "
                       "activate objects, and click contextual floating "
                       "labels."),
        ("Left Mouse / Space", "Compress, during compression sets. Hold for "
                               "the downstroke, release for full recoil."),
        ("C", "Crouch / kneel or stand up. Lets you kneel beside the casualty "
              "or stand up to reach the radio, fetch the AED, or stand clear."),
        ("G", "Drop / return a held item to its bench position."),
        ("Enter", "Confirm. Submits selections on review panels."),
        ("Tab", "Toggle HUD checklist display."),
        ("H", "Contextual help guide and directional indicator."),
        ("Esc / P", "Pause menu (Restart / Resume / Quit)."),
    ], "Input", "Action", widths=(38 * mm, 136 * mm)))

    # ------------------------------------------------------------------
    s.append(CondPageBreak(110))
    s.append(Paragraph("Phase 1: Before the Incident", h2))
    s.append(numbered([
        ("The brief",
         "An opening card sets the scene, explains the safety observer role "
         "and outlines the three phases of the exercise."),
        ("Identify the rescue kit",
         "Six of the seventeen items on the bench belong in a standard LV "
         "rescue kit: the kit bag, the insulated hook, the insulated gloves, "
         "the fire blanket, the torch and the DANGER ISOLATE HERE sign. Click "
         "each item to name it, then press Enter to review your claims."),
        ("Name the kit items",
         "Each claimed item is confirmed by name. Claims can be withdrawn and "
         "corrected at the bench before anything is submitted."),
        (crit("Put on insulated gloves"),
         "Take and don the LV insulated gloves from the bench before entering "
         "the switchboard area. Boots and long sleeves are assumed already "
         "worn."),
        ("Take the torch",
         "Stow the torch before work commences, so emergency lighting is ready "
         "if the power fails."),
        (crit("Identify the hazards"),
         "Examine the closed breaker board. A multi-selection list opens: "
         "identify the external electrical hazards present. Submit and "
         "confirm."),
        ("Open the board",
         "Interact with the breaker panel handle to swing the door open."),
        ("Reassess the hazards inside the open board",
         "Interact with the exposed interior. A second hazard list opens to "
         "identify what opening the board exposed - principally the live "
         "busbars. Confirm the assessment."),
        ("Hang the isolation sign",
         "Pick up the DANGER ISOLATE HERE sign from the bench and hang it on "
         "the designated isolation point. Once the sign is up, the co-worker "
         "enters the room to begin work."),
    ]))

    # ------------------------------------------------------------------
    s.append(CondPageBreak(110))
    s.append(Paragraph("Phase 2: Rescue", h2))
    s.append(numbered([
        ("The incident",
         "The worker begins work at the board and suffers an electric shock, "
         "frozen in tetanic contact with the live conductor. The contact "
         "clock starts immediately."),
        ("Retrieve the insulated rescue crook",
         "Quickly take the insulated rescue hook from the wall rack."),
        (crit("Break contact"),
         "Aim the crook at the worker's hips or torso and left-click to hook "
         "him clear of the conductor. Graded against a 20-second contact "
         "clock from the moment of the shock."),
        ("Get him clear, and the board dead",
         "Two tasks finish clearing the hazard zone:",
         [Paragraph("•  <b>Drag the casualty</b> to the marked safe "
                    "area clear of the board.", sub),
          Paragraph("•  <b>Isolate the circuit at the breaker</b>"
                    '<font color="#9d2f23"> *</font> - throw the '
                    "main switchboard isolator handle to OFF.", sub),
          Paragraph("Note on order - the taught order is drag clear first, "
                    "then isolate. Isolating first is recorded as a deviation "
                    "but not penalised. Never isolating the supply fails the "
                    "exercise.", note)]),
    ]))

    # ------------------------------------------------------------------
    s.append(CondPageBreak(110))
    s.append(Paragraph("Phase 3: Primary Survey (DRSABCD)", h2))
    s.append(Paragraph(
        "Kneeling at the casualty (press C, or click the casualty) displays "
        "floating labels anchored to the body parts. Pay close attention to "
        "order in this section.", body))
    s.append(numbered([
        ("Check he is not on fire",
         "Click the label near the torso to verify the casualty is not alight "
         "and his clothing is not smouldering."),
        ("Check for a response",
         "Click the label at the head to check vocal and physical "
         "responsiveness. The casualty is unresponsive."),
        ("Answer the choice card",
         "A decision prompt asks: “The casualty is unresponsive. What "
         "do you do first?” Select “Call for help”."),
        (crit("Call for help (send for an AED)"),
         "Press C to stand up, walk to the bench and activate the two-way "
         "radio. This calls 000 for emergency paramedics and requests an AED.",
         [Paragraph("<b>CRITICAL:</b> you MUST call 000 before opening the "
                    "airway or beginning compressions. Calling for help is a "
                    "prerequisite for the critical steps that follow.", warn)]),
        (crit("Open the airway"),
         "Return to the casualty, kneel (press C, or click the casualty) and "
         "select “Open the airway” at the head. The rescuer "
         "performs a head-tilt / chin-lift.",
         [Paragraph("<b>CRITICAL:</b> DO NOT perform this step before calling "
                    "for help on the radio. Doing it out of order causes an "
                    "automatic exercise failure.", warn)]),
        ("Look, listen and feel for breathing",
         "Hold the left mouse button for five seconds while aiming at the "
         "casualty's mouth. An ear indicator fills as you observe. The "
         "casualty is not breathing normally."),
        ("Check the airway for blockages",
         "Take the prompt to roll the casualty onto his side and visually "
         "inspect the mouth for foreign material. The airway is clear and he "
         "is rolled back supine."),
        ("Check for a carotid pulse",
         "A second five-second hold, at the side of the neck. No pulse is "
         "detected."),
    ]))

    # ------------------------------------------------------------------
    s.append(CondPageBreak(110))
    s.append(Paragraph("Phase 4: CPR and the AED", h2))
    s.append(numbered([
        ("First compression set",
         "Select “Start compressions”. Hands appear on the "
         "sternum and an audio metronome sounds at 110 BPM. Deliver 30 "
         "compressions through the shirt. Aim for 5–6 cm depth (hold "
         "each downstroke for about 180 ms) and release fully for recoil."),
        ("Open the shirt",
         "Between compression sets, take the prompt to unbutton the shirt so "
         "the chest is completely exposed for the defibrillator pads."),
        ("Fetch the AED",
         "Press C to stand up, walk to the AED cabinet shelf, take the unit "
         "and bring it back."),
        ("Place the AED",
         "Aim at the ghost outline on the floor beside the casualty's "
         "shoulder and left-click to place the unit. The AED powers on and "
         "begins spoken prompts."),
        ("Attach the pads",
         "Five ghost placement sites appear on the bare chest. Place the two "
         "correct pads: upper right chest, below the right clavicle, and "
         "lower left chest, on the mid-axillary line below the left armpit.",
         [Paragraph("Wrong sites are silently accepted by the unit but will "
                    "penalise the final AED score.", note)]),
        ("Stand clear and deliver the shock",
         "The AED announces “Analysing... Shock advised... Charging... "
         "Stand clear.” Press C to stand up and step clear of the "
         "casualty. Once charged and clear, click the flashing shock button "
         "on the AED to discharge."),
        ("Resume compressions",
         "Drop straight back down and deliver another full cycle of 30 chest "
         "compressions at 110 BPM."),
    ]))

    # ------------------------------------------------------------------
    s.append(CondPageBreak(110))
    s.append(Paragraph("Phase 5: Recovery and Handover", h2))
    s.append(numbered([
        ("Signs of life (ROSC)",
         "Spontaneous breathing returns. Stop compressions immediately."),
        (crit("Roll into the recovery position"),
         "Take the prompt to roll the breathing casualty onto his side to "
         "protect the airway.",
         [Paragraph("<b>CRITICAL:</b> do not attempt this before spontaneous "
                    "circulation and breathing have returned.", warn)]),
        ("Check for other injuries",
         "Perform a secondary survey with the casualty on his side: the head "
         "and neck, the legs and feet, and the hands - identifying the "
         "electrical entrance and exit contact burns."),
        ("Handover to paramedics",
         "The ambulance siren and emergency lights activate outside. Stand to "
         "meet the paramedics and hand over the incident history. The "
         "simulation then transitions to the debrief screen."),
    ]))

    # ------------------------------------------------------------------
    s.append(CondPageBreak(400))
    s.append(Paragraph("How a Run Can Fail (The Three Failure Conditions)", h2))
    s.append(Paragraph(
        "A run is graded against <b>26 procedure steps</b>. Reaching the 80% "
        "mark is necessary, but it is not sufficient on its own. A run ends "
        "in <b>EXERCISE NOT PASSED</b> if any of the three conditions below "
        "is met.", body))
    s.append(Spacer(1, 8))
    s.append(embed_diagram(DIAGRAM, doc.width, 280))
    s.append(Spacer(1, 10))

    s.append(Paragraph(
        "1. Instant fatal safety violations (zeroes the run immediately)", h3))
    s.append(Paragraph(
        "These are catastrophic errors in which the rescuer becomes a second "
        "casualty:", body))
    s.append(Paragraph(
        "•  <b>Touching an energised casualty.</b> Reaching for or "
        "contacting the worker with bare hands, or without both the insulated "
        "gloves and the rescue crook, while he is still touching the live "
        "conductor.", body))
    s.append(Paragraph(
        "•  <b>Delivering the AED shock while in contact.</b> "
        "Pressing the shock discharge button while still kneeling at the "
        "patient instead of standing up and stepping clear.", body))

    s.append(Paragraph("2. Score below the 80% pass mark", h3))
    s.append(Paragraph("Points are deducted for:", body))
    for item in [
        "Poor compression depth (below 75% of compressions reaching target "
        "depth) or an inconsistent rate.",
        "Incorrect AED pad positioning - the pad marks halve per misplaced "
        "pad.",
        "Missing real hazards, or ticking distractor hazards, during the "
        "board assessments.",
        "Taking longer than 20 seconds to break contact with the live "
        "conductor.",
        "Standard steps performed out of order - the score for that step is "
        "halved.",
    ]:
        s.append(Paragraph("•  " + item, body))

    s.append(Paragraph("3. Critical step violations (the 90%+ failure trap)",
                       h3))
    s.append(Paragraph(
        "Certain clinical and safety steps are designated critical "
        "(<font color='#9d2f23'><b>*</b></font>):", body))
    s.append(Paragraph(
        "•  If any critical step is missed, failed or performed out "
        "of order, the run is marked <b>EXERCISE NOT PASSED</b> regardless of "
        "the final score percentage - a 91% run with the airway opened before "
        "the 000 call still fails.", body))
    s.append(Paragraph(
        "•  In the debrief, critical steps are starred (*). If any "
        "starred step carries a “<font name='DejaVuSans'>!↓</font> "
        "too early” mark, or was omitted, the header displays: "
        "<b>“Critical step(s) performed out of order: [Step "
        "Name]”</b>.", body))

    # ------------------------------------------------------------------
    s.append(CondPageBreak(110))
    s.append(Paragraph(
        "Complete Table of Critical Steps (*) & Ordering Traps", h2))
    s.append(Paragraph(
        "Seven steps carry the critical mark. Their prerequisites are "
        "checked against everything that must already have happened - if a "
        "critical step runs ahead of any of them, the run fails outright.",
        body))
    crit_rows = [
        ('Don correct PPE <font color="#9d2f23"><b>*</b></font>',
         "None - must be done at the start.",
         "Approaching the live board, touching the crook, or touching the "
         "casualty without gloves on."),
        ('Identify electrical hazard <font color="#9d2f23"><b>*</b></font>',
         "None.",
         "Opening the breaker door before identifying the external board "
         "hazard."),
        ('Break contact with hazard <font color="#9d2f23"><b>*</b></font>',
         "Don PPE & retrieve the crook.",
         "Touching or hooking the casualty before having both gloves on and "
         "the crook equipped."),
        ('Isolate the circuit <font color="#9d2f23"><b>*</b></font>',
         "Break contact with the crook.",
         "Never isolating the switchboard. (Dragging first or isolating "
         "first are both acceptable.)"),
        ('Call for help (send for AED) '
         '<font color="#9d2f23"><b>*</b></font>',
         "Casualty found unresponsive (check_response).",
         "Proceeding with resuscitation without calling 000 on the radio."),
        ('Open the airway <font color="#9d2f23"><b>*</b></font>',
         "Call for help (send_for_help) & check response.",
         '<b>Clicking “Open the airway” on the casualty before '
         'calling 000 on the radio.</b> The most common cause of 90%+ run '
         "failures."),
        ('Roll into recovery position '
         '<font color="#9d2f23"><b>*</b></font>',
         "Return of spontaneous breathing (signs_of_life).",
         "Attempting to roll the casualty into the recovery position while he "
         "is still pulseless and unresponsive, before CPR achieves ROSC."),
    ]
    crit_table = three_col(
        ["Critical step (*)", "Prerequisites required before this step",
         "What causes an out-of-order failure"],
        crit_rows, widths=[40 * mm, 52 * mm, 82 * mm])
    s.extend(keep_if_fits([crit_table], None, 300))

    # ------------------------------------------------------------------
    s.append(CondPageBreak(150))
    s.append(Paragraph("Debrief Screen Legend", h2))
    s.append(Paragraph(
        "When reviewing the final score screen, every step carries one of the "
        "following marks:", body))
    legend_rows = [
        ("✓ in order",
         "Step completed with correct clinical timing and prerequisites."),
        ("!↓ too early",
         "The step was completed, but before one or more of its mandatory "
         "prerequisites were finished. If this appears on a starred (*) "
         "critical step, the exercise is an automatic fail."),
        ("↑ overtaken",
         "The step was skipped earlier and only completed after a later step "
         "had already been triggered."),
        ("! late",
         "The step was performed in order, but exceeded its clinical time "
         "limit - for example taking more than 20 seconds to break contact."),
        ("✕ error",
         "The step failed or violated protocol."),
        ("— not attempted",
         "The step was completely missed."),
        ("* critical",
         "A mandatory safety or clinical step where 100% compliance and "
         "flawless sequence order are required to pass."),
    ]
    legend_data = [[Paragraph("<b>Mark</b>", bold),
                    Paragraph("<b>Meaning</b>", bold)]]
    for mark, meaning in legend_rows:
        legend_data.append([
            Paragraph("<b>%s</b>" % mark, symbol),
            Paragraph(meaning, small)])
    legend = Table(legend_data, colWidths=[32 * mm, 142 * mm], hAlign="CENTER",
                   repeatRows=1)
    legend.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("BACKGROUND", (0, 0), (-1, 0), BAND),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LEFTPADDING", (0, 0), (-1, -1), 5),
        ("LINEBELOW", (0, 0), (-1, -2), 0.3, RULE),
        ("BOX", (0, 0), (-1, -1), 0.3, RULE),
    ]))
    s.extend(keep_if_fits([legend], None, 300))

    doc.build(s)
    print("wrote", OUT)


if __name__ == "__main__":
    build()
