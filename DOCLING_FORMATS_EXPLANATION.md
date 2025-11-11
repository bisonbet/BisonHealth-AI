# Docling Formats Usage Explanation

## What Gets Sent to the AI Doctor

When you select a medical document for AI context, here's what actually gets sent:

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

## Where JSON is Used

**JSON format is essential** for structured extraction:

1. **Section Extraction** (`MedicalDocumentExtractor.extractSections()`):
   - Parses JSON structure (`body.children`)
   - Uses `label` field to identify headings (e.g., "heading", "title")
   - Groups paragraphs under their headings
   - Creates `DocumentSection` objects with `sectionType` and `content`

2. **Text Extraction** (`MedicalDocumentExtractor.extractFullText()`):
   - Extracts all text from JSON structure recursively
   - This becomes `extractedText` in the database
   - Used as fallback if section extraction fails

## Where Markdown is Used

**Markdown is currently redundant** but kept as a safety net:

1. **Stored but not actively used**: Markdown from Docling is stored in `result.extractedText` but we extract text from JSON instead
2. **Fallback only**: If JSON parsing fails completely, markdown could be used
3. **Future use**: Could be used for display/rendering in the UI

## Current Flow

```
Docling Request:
  ├─ Request: md + json formats
  
Docling Response:
  ├─ md_content: Markdown text (currently unused)
  └─ json_content: Structured JSON with body.children
  
Processing:
  ├─ JSON → MedicalDocumentExtractor
  │   ├─ extractSections() → Creates sections from JSON structure
  │   └─ extractFullText() → Extracts text from JSON structure
  │
  └─ Markdown → Stored but not used (redundant)
  
AI Context:
  ├─ If sections exist → Send organized sections
  └─ If no sections → Send extractedText (from JSON, not markdown)
```

## Recommendation

**We could optimize by only requesting JSON**, since:
- Sections come from JSON structure
- Text extraction comes from JSON structure  
- Markdown is stored but not used

However, keeping markdown provides:
- Safety net if JSON parsing fails
- Future UI rendering capabilities
- Easier debugging (markdown is human-readable)

## Answer to Your Question

**What's sent to AI doctor?**
- **Sections** (extracted from JSON) - organized by type like "Findings:", "Impression:"
- **Fallback**: Full text (extracted from JSON, not markdown)

**Why do we need JSON?**
- JSON structure (`body.children` with `label` fields) is the ONLY way to programmatically identify section boundaries
- Markdown doesn't have structured labels - it's just text with formatting

**Why do we request markdown?**
- Currently redundant - we extract everything from JSON
- Kept as safety net and for potential future use

