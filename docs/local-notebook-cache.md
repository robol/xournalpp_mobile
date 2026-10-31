# Local notebook cache

On Android, iOS and desktop, local notebook caching is enabled by default. Settings
contains a switch, the cache's disk usage and a **Clear cache** action. Disabling
caching stops reads and writes without deleting existing copies. Clearing removes
cached notebooks and PDF resources, but preserves crash-recovery drafts.

Each provider/account and notebook has its own entry. Successful opens and saves
provide a baseline; idle and lifecycle checkpoints retain recent unsaved edits.
Explicitly discarding edits restores the baseline. Copies are retained until
cleared, so storage usage can grow. Browser caching is not implemented.

The app always tries the original storage first. If a provider read or account
restoration fails, it can offer the local copy with its checkpoint time. A
successful download that fails notebook parsing is reported as a document error.
The launcher also offers **Cached notebooks**, and failed provider listings offer
their cached entries. Cached notebooks can be opened without reconnecting an
account; saving to that account requires reconnecting, or saving a copy elsewhere.

A cached copy may be outdated. Its editor displays a persistent warning and
requires explicit confirmation before overwriting an original, including existing
Save As destinations. There is no automatic synchronization or remote version
check. A failed save leaves the document dirty and the warning visible. Saving a
copy is available without overwriting the original.

PDFs are stored as content-addressed blobs shared between snapshots. Notebook
checkpoints do not wait for PDF downloads. Until all backgrounds are cached, the
copy is explicitly marked incomplete, and unavailable PDFs use the existing
missing-background recovery flow. Snapshot manifests are published atomically
only after their referenced blobs are written. Clearing invalidates pending
writes, and failed cache operations do not make a successful provider operation
fail. Cache files live in the application's support directory and contain notebook
and PDF data, not provider credentials.
