# Historical Docling Formats Note

This document describes the former Docling server integration. It is retained for
historical/legacy compatibility only. The current app does not require or call a
Docling server.

The active document path is `NativeDocumentExtractor` (PDFKit and Vision OCR),
orchestrated by `DocumentProcessor`. Structured medical data is then handled by
`MedicalDocumentExtractor`.

## Historical AI-Context Formatting

When the former integration supplied a medical document for AI context, the
following representations were used:

### Primary Path (Preferred): Sections from JSON
```
[Imaging Report from Nov 10, 2025 - Provider Name]
File: document.pdf

Findings:
[Content from Findings section]

Impression:
[Content from Impression section]
```

### Fallback Path: Full Text
If sections aren't extracted, it falls back to:
```
[Imaging Report from Nov 10, 2025 - Provider Name]
File: document.pdf

Document Content:
[Full document text, truncated to 5000 chars]
```

## Historical JSON Handling

**JSON format was essential** for structured extraction in that integration:

1. **Section Extraction** (`MedicalDocumentExtractor.extractSections()`):
   - Parses JSON structure (`body.children`)
   - Uses `label` field to identify headings (e.g., "heading", "title")
   - Groups paragraphs under their headings
   - Creates `DocumentSection` objects with `sectionType` and `content`

2. **Text Extraction** (`MedicalDocumentExtractor.extractFullText()`):
   - Extracts all text from JSON structure recursively
   - This becomes `extractedText` in the database
   - Used as fallback if section extraction fails

## Historical Markdown Handling

**Markdown was redundant** in that implementation but was kept as a safety net:

1. **Stored but not actively used**: Markdown from Docling was stored in `result.extractedText`, while text was extracted from JSON instead
2. **Fallback only**: If JSON parsing fails completely, markdown could be used
3. **Future use**: Could be used for display/rendering in the UI

## Historical Flow

```
Former Docling request:
  ├─ Request: md + json formats
  
Former Docling response:
  ├─ md_content: Markdown text (unused in that implementation)
  └─ json_content: Structured JSON with body.children
  
Former processing:
  ├─ JSON → MedicalDocumentExtractor
  │   ├─ extractSections() → Creates sections from JSON structure
  │   └─ extractFullText() → Extracts text from JSON structure
  │
  └─ Markdown → Stored but not used (redundant)
  
Historical AI context:
  ├─ If sections exist → Send organized sections
  └─ If no sections → Send extractedText (from JSON, not markdown)
```

## Historical Recommendation

The former implementation could have requested only JSON, since:
- Sections come from JSON structure
- Text extraction comes from JSON structure  
- Markdown is stored but not used

However, keeping markdown provides:
- Safety net if JSON parsing fails
- Future UI rendering capabilities
- Easier debugging (markdown is human-readable)

## Historical Answers

**What was sent to the AI doctor?**
- **Sections** (extracted from JSON) - organized by type like "Findings:", "Impression:"
- **Fallback**: Full text (extracted from JSON, not markdown)

**Why did that implementation need JSON?**
- JSON structure (`body.children` with `label` fields) is the ONLY way to programmatically identify section boundaries
- Markdown doesn't have structured labels - it's just text with formatting

**Why did that implementation request markdown?**
- It was redundant - the implementation extracted everything from JSON
- It was kept as a safety net and for potential future use
