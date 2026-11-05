# PDF export fixtures

linearized-xref-stream.pdf is synthetic and contains two 200 × 200 point pages,
each drawing a green rectangle. Its title is "Synthetic public regression
fixture". It contains no private document content.

It was generated from a simple classic-table PDF using qpdf 12.2.0:

    qpdf --object-streams=generate --linearize source.pdf linearized-xref-stream.pdf

The resulting file has cross-reference streams, compressed objects, and a final
startxref pointing to the early cross-reference section rather than the last
physical section. The PDF exporter tests check this property before exporting.

The independent integration test requires qpdf and Ghostscript. Executable
paths can be supplied with PDF_EXPORT_QPDF and PDF_EXPORT_GS. It runs qpdf
--check, rasterizes every page with Ghostscript while rejecting repair warnings,
and checks green background and blue handwriting pixels across two exports.
Without these executables, that integration test reports a skip.
