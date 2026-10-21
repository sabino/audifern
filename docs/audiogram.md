# Local audiogram records

Audifern's **Audiogram** tab stores values copied from an existing exam. It does not play test tones, calculate a hearing-aid prescription, or send audiometric values to an aid. A local sound preset can reference an exam UUID as metadata; that association performs no conversion or fitting.

The editor, Settings and device information share the main application window.
The app owns the draft for its lifetime, so switching tabs or closing and
reopening the main window preserves edits. Quitting still requires saving an
exam to retain it. HIMSA export options expand inline; choosing an actual file
uses the normal attached macOS file picker.

The editor records both ears at 125, 250, 500, 750, 1000, 1500, 2000, 3000, 4000, 6000 and 8000 Hz. Air and bone conduction, masked and unmasked conditions, and no-response flags remain distinct. Empty cells mean unrecorded, including an unknown exam date. A no-response entry stores the presentation level from the exam rather than claiming a threshold was measured. Values are not extrapolated or filled from the opposite ear.

The plot uses a logarithmic frequency axis and a linear dB HL axis increasing downward. One octave spans the same distance as 20 dB. The supported input and display range is −20 through 130 dB HL; this is a data-entry boundary, not a device gain or output range. Only entered points are drawn. The table is the authoritative numeric representation; no-response arrows and the legend distinguish those entries from measured thresholds.

The saved-fitting inspector has a separate table for values recovered from an
aid backup. That format omits the original exam date and measurement units, and
may contain interpolated/rounded or uncorrected ABR/nHL values. They are not
automatically converted into an exam. After explicitly confirming dB HL units
against the source exam, the user can copy ordinary AC/BC response points into
a new unsaved editor draft. NR, uncertain, UCL and in-situ entries remain in the
private backup; masked ordinary responses retain their condition. Saved exams
remain unchanged until an explicit save, and replacing an unsaved draft requires
a separate confirmation. This does not calculate or program a fitting.

Exam names, optional dates and notes are kept in `~/Library/Application Support/Audifern/audiograms.json`. The directory has 0700 permissions and the file is atomically replaced with 0600 permissions from its first written byte. No values are logged, included in the repository, uploaded, or sent through BLE. Invalid, unsupported or oversized imports fail without replacing the saved file. New-exam/discard, clear and deletion actions ask for confirmation when data would be removed. JSON import first opens a draft for review; **Save exam** explicitly persists it.

# HIMSA Audiogram 502 export

The optional XML export emits the official Audiogram 502 structure as a measurement interchange file. It is not a Noah patient database, a complete Noah `.nhax`/`.nha` export, or a fitting module. Noah-side ingestion needs compatible software and is unverified here. XML never sets `ValidatedByNOAH` or invents instrument/calibration data. The format has no root exam-date field; the full date/name/notes remain in the JSON record.

The user selects the recorded air-conduction transducer (headphones or insert earphones). The test signal remains `Unknown` unless specified. Measured dB HL values and no-response presentation levels are preserved with at most one decimal place; values requiring rounding block XML export. Masked results currently block XML export because the editor does not record the actual masking stimulus levels required by HIMSA's documented rules. JSON preserves those measurements without inventing missing masking data.

The schema is acquired privately from HIMSA; it is not redistributed. For local validation, set `HIMSA_AUDIOGRAM_SCHEMA` to its path when running `swift test`. The schema test emits a synthetic four-curve exam and validates it with macOS's `xmllint --nonet --schema`. Ordinary tests also check XML structure, no-response semantics, missing metadata handling, corrupt imports and private atomic persistence.

# Sources

- [ASHA, Guidelines for Manual Pure-Tone Threshold Audiometry](https://www.asha.org/policy/GL2005-00014/): measurement units, ordinary test frequencies, air/bone distinction and record-keeping conventions. Accessed 2026-10-20.
- [ASHA, Audiometric Symbols](https://www.asha.org/policy/GL1990-00006/): logarithmic frequency grid, downward hearing-level axis, chart geometry, right/left and masked/unmasked symbols. Accessed 2026-10-20.
- [HIMSA Audiogram Format](https://himsanoah.atlassian.net/wiki/spaces/AD/pages/1312653313/Audiogram+Format), version 502 revision 6 XSD: namespace, element order, condition enums, one-decimal precision and masking metadata rules. SHA-256 `39ea4a363fbfce4837ef51c08083377e10b6bc662124eb8bb3daaefe89442eb2`. The schema is privately acquired; acquisition details are in [the Noah investigation](noah-investigation.md).
