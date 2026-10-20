# Public-source preparation

This ledger records a local privacy review, rather than a legal clearance or a
guarantee that every possible identifier can be recognized automatically.
Publication is a separate action requiring the project owner's approval.

## Baseline reviewed

The initial review on 2026-10-20 covered commit `62dda0d`, every branch and tag,
all five commits, all 138 stored blobs (including one dangling blob), tracked
resources, and the categories of ignored local artifacts. There was one local
branch and no tags or remotes at that point.

The review found:

- All five commits contained personal author/committer identities and embedded
  signatures. A source-only cleanup would leave that information in history.
- No personal home directory, personal email address, credential literal or
  private-key PEM was identified in the stored source blobs. Exact comparisons
  against the locally provisioned authentication key and both device serials
  found no matches. Serial test vectors were separately reviewed as synthetic.
- An owner-derived reverse-DNS application identifier remained in the plist and
  build script. A neutral namespace is needed if the release should contain no
  owner-derived identifier.
- The tracked resources contained only the application's plist. No APK,
  extracted library, vendor image, fitting module, firmware image, HIMSA schema,
  capture, or locally signed application bundle was tracked.
- No source license had been selected. A public release needs an explicit
  license and a clear separation between this implementation and third-party
  materials used privately during research.

These are baseline observations. Run the checks again after branding, UI,
localization, documentation and history changes.

## Private material to preserve locally

`private/` contains acquired applications, extracted managed/native code,
decoded resources, analysis evidence, device identifiers, medical drafts,
accessibility captures and screenshots. Its approximate size at the initial
review was 1.5 GB. It is an investigation workspace, not a public artifact.
`build/` and `.build/` contain local binaries, compiler paths and signing
metadata. Their exclusion is deliberate even when the source is clean.

Authentication material is provisioned outside the application bundle in the
user's Application Support directory. Provisioning scripts must not embed,
print or download it. Direct consumer controls can work without this material;
advanced UTL features depend on a separately obtained compatible credential.
The public source must describe that dependency without redistributing the
credential or proprietary SDK code.

Do not delete local evidence to prepare a release. Preserve the private work
and make a separate public export containing only reviewed tracked files.
Any screenshots or example exams intended for the README must use explicitly
synthetic devices, identifiers and audiograms.

## History cleanup checklist

1. Finish and review the intended source changes. Record the current status and
   diff so unrelated or unsaved work is preserved.
2. Make a private, permission-restricted recovery archive **outside the future
   public export**. Preserve the entire original `.git` directory, working
   changes and private artifacts. A Git bundle is useful in addition to that
   archive, but does not preserve all dangling objects, reflogs or local config.
3. Review every ref, not only the current branch. Replace personal author and
   committer identities with an explicitly approved public identity, and strip
   old commit and annotated-tag signatures. Review commit/tag messages as well
   as file contents. Signatures made with the old identity must not survive as
   embedded metadata.
4. Remove or rewrite any sensitive paths and values identified in historical
   blobs. Do not leave `refs/original`, backup branches, old tags or other refs
   pointing at the old objects in the public repository.
5. After validating the private recovery copy, expire the rewritten public
   repository's reflogs and prune its old unreachable objects. This is a
   deliberate final cleanup, not something the read-only scanner performs.
6. Re-run the audit on the prepared repository, including all stored objects.
   Verify a fresh clone/export independently and confirm private directories,
   local credentials and signed build products are absent.
7. Keep the original recovery archive private. Do not upload the original
   `.git` directory, the investigation workspace, or an unreviewed ZIP of the
   development directory.

History rewriting changes commit IDs. Existing local evidence may continue to
refer to the original private IDs; those references are provenance, not refs
that should preserve the old personal metadata in the public repository.

## Repeatable checks

The independent standard-library checker reads both current non-ignored source
files and **all stored Git objects**, including dangling commits and blobs. It
prints categories, file paths, line numbers and object IDs, never matching
values. A finding is an item requiring review, not an automatic assertion that
the contents are a live secret.

```sh
python3 scripts/audit-public-source.py
```

The public contributor identity must be explicit when inspecting history:

```sh
python3 scripts/audit-public-source.py \
  --allow-identity 'Project Contributors <contributors@example.invalid>'
```

For the owner's final local review, place exact private values in an ignored
JSON file containing objects with either a `text` or `hex` field. Include known
serials, device identifiers, account details, home paths and authentication
material. The file itself must never be staged or included in an export:

```sh
python3 scripts/audit-public-source.py \
  --allow-identity 'Project Contributors <contributors@example.invalid>' \
  --private-pattern-file private/public-audit-patterns.json
```

The matcher is exact for supplied private patterns. Manually inspect formatting
variants, embedded image metadata, generated artwork, copied code and binary
resources; absence of a pattern match does not establish that those are safe.
Known protocol UUIDs, document hashes, method tokens and deliberately synthetic
test vectors are not device credentials by themselves. The reviewer must keep
that distinction explicit.

PNG artwork is inspected as a structured file. Heuristic email, home-path and
credential checks apply to non-pixel metadata, decoded textual chunks and
appended bytes, rather than random compressed IDAT/APNG pixel data. Supplied
exact private patterns still match against the **entire original binary** and
decoded metadata. PNG chunk bounds/CRCs and text decompression are checked;
malformed, truncated or oversized metadata produces a review finding instead
of silently passing. Decoded metadata findings point to the original chunk's
position, not a fictitious source-text line. This is not an image decoder or
OCR check: visually rendered identifiers still require a screenshot review.
The parsing follows the [W3C PNG specification](https://www.w3.org/TR/png-3/).

Before publication, also review the source license, third-party notices, feature
claims, tested hardware scope and independent-project wording. Do not imply
vendor endorsement or that an untested fitting/firmware operation is supported.
