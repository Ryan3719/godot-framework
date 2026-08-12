# Content Delivery

## Release Layout

Content is staged below the project-owned `GFContentSettings.base_directory`:

```text
content/
  activation.json
  releases/
    release-id/
      release.json
      base.pck
      optional/extra.pck
```

`release.json` is an installation record created by the framework after verification. The downloaded manifest and its detached signature remain byte-for-byte inputs to later validation.

## Manifest

Schema version 1 is a UTF-8 JSON object:

```json
{
  "schema_version": 1,
  "release_id": "2026.08.12.1",
  "packs": [
    {
      "id": "base",
      "path": "base.pck",
      "sha256": "64-lowercase-hex-characters",
      "size": 123456,
      "replace_files": true,
      "offset": 0
    }
  ]
}
```

Sign the SHA-256 digest of the exact manifest bytes with the release RSA private key. Configure only the public PEM key in `GFContentSettings`. Reformatting JSON changes its bytes and invalidates its detached signature by design.

## Activation Flow

1. Download packs into paths returned by `GFContentService.pack_path()`.
2. Verify all download tasks completed.
3. Call `install_release(manifest_text, signature)` to validate the signature, schema, paths, sizes, and hashes and write the installation record.
4. Call `activate_release(release_id)` to persist the active/previous pointer.
5. Restart when `restart_required` is true. The content module mounts the active release during its next startup.

If startup validation or mounting fails, the activation pointer is restored to the previous release. If at least one PCK was already mounted, the process is tainted because Godot cannot unload it; further mounts are rejected and the application must restart.

## Threat Model

The signed manifest protects against an attacker modifying CDN responses or locally staged packs without access to the release private key. Length and SHA-256 checks detect truncation and corruption. Safe path validation prevents a manifest from escaping its release directory.

This does not protect a fully compromised client device. An attacker controlling the process can patch verification code, replace the embedded public key, inspect content, or modify memory after verification. TLS remains required to protect availability and metadata in transit even though signatures authenticate release content.

Keep signing keys offline, rotate compromised keys through an application update, use monotonic release policy in application code when downgrade prevention matters, and never place authoritative secrets or trust decisions inside downloadable game content.
