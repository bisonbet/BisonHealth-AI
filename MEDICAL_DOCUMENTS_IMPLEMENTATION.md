# Medical Documents OCR Import - Implementation Summary

## Overview
This implementation adds comprehensive support for importing, OCRing, and managing medical documents (doctor's notes, imaging reports, lab reports, etc.) in BisonHealth-AI. Documents are processed using docling to extract structured data, which can then be selected for inclusion in AI doctor conversations.

## Key Features Implemented

### 1. Enhanced Data Model (`MedicalDocument.swift`)

**New Medical Document Model:**
- `MedicalDocument` - Extended document model with medical-specific fields:
  - `documentDate` - Date of the medical visit/report
  - `providerName` - Doctor or facility name
  - `providerType` - Category (doctor, imaging center, lab, hospital, etc.)
  - `documentCategory` - Type of document (doctor's note, imaging report, lab report, etc.)
  - `extractedText` - Full OCR'd text
  - `rawDoclingOutput` - Complete DoclingDocument JSON
  - `extractedSections` - Structured sections (Findings, Impressions, etc.)
  - `includeInAIContext` - Boolean flag for AI doctor context selection
  - `contextPriority` - Priority ranking (1-5) for context inclusion
  - `lastEditedAt` - Track manual edits

**Supporting Types:**
- `ProviderType` enum - Primary care, specialist, imaging center, laboratory, hospital, urgent care, pharmacy
- `DocumentCategory` enum - 11 types including doctor's note, imaging report, lab report, prescription, discharge summary, operative report, pathology report, consultation, vaccine record, referral
- `DocumentSection` - Represents extracted sections with type, content, confidence score
- `DoclingDocument` - Full model for docling JSON output structure

### 2. Database Schema Updates (`DatabaseManager.swift`)

**Migration to v4:**
- Added 10 new columns to documents table:
  - `document_date`, `provider_name`, `provider_type`
  - `document_category`, `extracted_text`, `raw_docling_output`
  - `extracted_sections`, `include_in_ai_context`
  - `context_priority`, `last_edited_at`
- Created indexes for:
  - `document_date` - Fast date range queries
  - `document_category` - Filter by document type
  - `include_in_ai_context` - Quick AI context retrieval

**Database Operations (`DatabaseManager+MedicalDocuments.swift`):**
- `saveMedicalDocument()` - Save with all medical fields
- `fetchMedicalDocuments()` - Get all documents
- `fetchDocumentsForAIContext()` - Get only documents selected for AI (sorted by priority and date)
- `fetchMedicalDocuments(category:)` - Filter by document type
- `fetchMedicalDocuments(providerName:)` - Filter by provider
- `fetchMedicalDocuments(from:to:)` - Date range queries
- `updateDocumentAIContextStatus()` - Toggle AI context inclusion
- `searchMedicalDocuments()` - Full-text search across filename, provider, and extracted text

### 3. Medical Document Extraction Service (`MedicalDocumentExtractor.swift`)

**Intelligent Extraction Pipeline:**
1. **Parse docling output** - Extract full text and detect sections
2. **AI-enhanced extraction** (if available) - Use AI to:
   - Extract document date
   - Identify provider name and type
   - Classify document category
   - Parse structured sections
3. **Fallback extraction** - Pattern matching for:
   - Date extraction from filename (YYYY-MM-DD, MM-DD-YYYY formats)
   - Date extraction from text (multiple formats supported)
   - Document category detection via keywords
   - Provider information extraction

**Document Category Auto-Detection:**
- Imaging Report: Keywords like "radiology", "CT scan", "MRI", "findings", "impression"
- Lab Report: "laboratory", "test results", "reference range"
- Prescription: "prescription", "rx:", "medication", "dispense"
- Discharge Summary: "discharge summary", "hospital course", "admission date"
- Operative Report: "operative report", "procedure performed", "surgeon"
- Pathology Report: "pathology", "biopsy", "microscopic description"
- And more...

### 4. AI Chat Context Integration

**Updated `ChatContext` Model:**
- Added `medicalDocuments: [MedicalDocumentSummary]` field
- `MedicalDocumentSummary` - Lightweight representation for AI context:
  - Document metadata (date, provider, category)
  - Extracted sections
  - Priority for sorting

**Context Building (`ChatModels.swift`):**
- `buildContextString()` updated to include medical documents section
- Documents sorted by:
  1. Context priority (highest first)
  2. Document date (newest first)
- Each document formatted as:
  ```
  [DocumentCategory from Date - Provider]

  Section Name:
  Section content...
  ```

**Token Estimation:**
- Updated to account for medical document sections
- ~4 characters per token estimation
- Header: 50 tokens per document
- Content: actual character count / 4

### 5. AI Chat Manager Updates (`AIChatManager.swift`)

**Medical Document Loading:**
- `updateHealthDataContext()` - Now async, fetches documents from database
- Only includes documents where `includeInAIContext = true`
- Converts to `MedicalDocumentSummary` for efficient context usage

**Context Building:**
- `buildHealthDataContext()` - Now async to support database queries
- Includes debug logging for medical documents count
- Maintains existing compression logic for large contexts

## Document Processing Workflow

### Current Flow (Unchanged):
1. User imports document (PDF, DOCX, image, etc.)
2. Document stored encrypted in filesystem
3. Added to processing queue
4. Sent to docling for OCR/parsing
5. Results stored in database

### Enhanced Flow (New):
6. **Medical extraction service processes docling output:**
   - Extracts full text
   - Identifies document sections
   - Uses AI (if available) to extract:
     - Document date
     - Provider information
     - Document category
     - Structured sections
7. **Medical metadata saved to database:**
   - All extracted fields stored
   - Raw docling JSON preserved
   - Document ready for review/editing

### AI Context Inclusion Flow (New):
1. User reviews document in UI
2. User toggles "Include in AI Context" switch
3. Document marked with `includeInAIContext = true`
4. When chatting with AI doctor:
   - System fetches all documents with flag=true
   - Converts to summaries
   - Includes in context string
   - AI receives structured medical information

## Data Fields Summary

### Essential Fields:
- **documentDate** - When the medical event occurred (not import date)
- **providerName** - "Dr. Smith" or "City MRI Center"
- **providerType** - Categorizes the provider
- **documentCategory** - Type of medical document
- **extractedSections** - Structured content (Findings, Impressions, etc.)

### Content Fields:
- **extractedText** - Full OCR'd text for search
- **rawDoclingOutput** - Complete docling JSON for advanced features
- **extractedHealthData** - Linked health data items (blood tests, etc.)

### AI Context Fields:
- **includeInAIContext** - User's selection flag
- **contextPriority** - 1-5 ranking (5 = highest priority)

### Metadata Fields:
- **importedAt** - When document was uploaded
- **processedAt** - When OCR completed
- **lastEditedAt** - Track manual edits
- **notes** - User notes about the document
- **tags** - User-defined tags for organization

## Database Design

### Schema (v4):
```sql
CREATE TABLE documents (
    -- Existing fields
    id TEXT PRIMARY KEY,
    file_name TEXT NOT NULL,
    file_type TEXT NOT NULL,
    file_path TEXT NOT NULL,
    thumbnail_path TEXT,
    processing_status TEXT NOT NULL,
    imported_at INTEGER NOT NULL,
    processed_at INTEGER,
    file_size INTEGER NOT NULL,
    tags TEXT NOT NULL,
    notes TEXT,
    extracted_data BLOB,

    -- New medical fields (v4)
    document_date INTEGER,
    provider_name TEXT,
    provider_type TEXT,
    document_category TEXT DEFAULT 'other',
    extracted_text TEXT,
    raw_docling_output BLOB,
    extracted_sections BLOB,
    include_in_ai_context INTEGER DEFAULT 0,
    context_priority INTEGER DEFAULT 3,
    last_edited_at INTEGER
);

-- Indexes for performance
CREATE INDEX idx_documents_date ON documents(document_date);
CREATE INDEX idx_documents_category ON documents(document_category);
CREATE INDEX idx_documents_ai_context ON documents(include_in_ai_context);
```

### Migration Strategy:
- Backward compatible - existing documents get default values
- Non-destructive - ALTER TABLE ADD COLUMN with defaults
- Automatic backup before migration
- Step-by-step versioned migrations

## Next Steps (UI Implementation)

### 1. Document Review UI
- Display extracted metadata (date, provider, category)
- Show extracted sections in expandable format
- Edit functionality for all fields
- Document preview with highlighting

### 2. Document Selection UI
- List view of all processed documents
- Toggle switch for "Include in AI Context"
- Priority slider (1-5)
- Visual indicator of what's included
- Context size preview/warning

### 3. AI Chat UI Enhancement
- Show selected documents indicator
- Button to manage document selection
- Preview of included context
- Document references in AI responses

### 4. Document Management
- Bulk operations (select multiple, toggle context)
- Filter by category, provider, date range
- Search across all fields
- Export functionality

## Testing Recommendations

### Unit Tests:
- MedicalDocumentExtractor date parsing
- Document category detection
- Section extraction from docling output
- Context string building with medical documents

### Integration Tests:
- End-to-end document import and extraction
- Database CRUD operations
- AI context building with multiple documents
- Migration from v3 to v4

### UI Tests:
- Document review and editing workflow
- Context selection and priority setting
- AI chat with medical documents
- Search and filtering

## Performance Considerations

- **Database Indexes**: Fast queries for AI context retrieval
- **Lazy Loading**: Only load full sections when needed
- **Context Compression**: Existing logic handles large contexts
- **Prioritization**: High-priority docs loaded first

## Security & Privacy

- All medical data encrypted in database (existing)
- Files encrypted on filesystem (existing)
- Sensitive fields (extracted_text, sections) stored as BLOBs
- No medical data in logs (except debug mode)

## File Structure

```
HealthApp/HealthApp/
├── Models/
│   └── MedicalDocument.swift (NEW)
├── Database/
│   ├── DatabaseManager.swift (UPDATED - v4 migration)
│   └── DatabaseManager+MedicalDocuments.swift (NEW)
├── Services/
│   └── MedicalDocumentExtractor.swift (NEW)
└── Managers/
    └── AIChatManager.swift (UPDATED - async context)
```

## Summary

This implementation provides a solid foundation for medical document management with:
- ✅ Comprehensive data model for medical documents
- ✅ Database schema with medical-specific fields
- ✅ Intelligent extraction from docling output
- ✅ AI-powered metadata extraction
- ✅ Context selection and prioritization
- ✅ Integration with AI doctor chat

The backend is fully implemented and ready for UI development. The system can:
- Import and OCR medical documents
- Extract structured medical information
- Store all data securely in the database
- Include selected documents in AI conversations
- Support editing and management of document metadata
