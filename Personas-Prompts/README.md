# Personas & Prompts Directory

This directory contains system prompts and templates used throughout the BisonHealth AI application.

## Doctor Personas

Doctor personas are used in the chat interface to provide specialized medical advice:

- `primary_care.txt` / `primary_care_tight.txt` - General family medicine
- `internal_medicine.txt` / `internal_medicine_tight.txt` - Internal medicine specialist
- `clinical_nutritionist.txt` / `clinical_nutritionist_tight.txt` - Nutrition and diet
- `exercise_specialist.txt` / `exercise_specialist_tight.txt` - Exercise physiology
- `orthopedic_specialist.txt` / `orthopedic_tight.txt` - Bone and joint health
- `physical_therapist.txt` / `physical_therapist_tight.txt` - Physical rehabilitation
- `dentist_tight.txt` / `orthodontist_tight.txt` - Dental health
- `root_cause_analysis.txt` - Long-term health pattern analysis
- `best_doctor.txt` - Comprehensive medical AI assistant
- `daveshap_chronic_health_ai.txt` - Chronic condition management

**Tight vs. Regular**: "Tight" versions are optimized for mobile use with shorter prompts and faster generation.

## Task-Specific Prompts

### Blood Test Extraction

Used by `BloodTestMappingService.swift` to extract lab values from medical documents:

- **`blood_test_extraction_prompt_optimized.txt`** (Current) - ~500 tokens, optimized for speed
- **`blood_test_extraction_prompt_verbose.txt`** (Archived) - ~1400 tokens, original verbose version

**Optimization History** (2025-12-30):
- Reduced prompt from 1400 → 500 tokens (64% reduction)
- Removed exhaustive test lists (model already knows medical tests)
- Reduced examples from 13 → 4
- Simplified verbose instructions
- **Performance gain**: ~50% faster prefill time (~15-35s saved per 2000-char chunk)
- **Quality impact**: No degradation expected (kept critical deduplication logic)

## Usage Notes

- Doctor personas are loaded via `Doctor.swift` model
- Blood test extraction prompt is in `BloodTestMappingService.extractLabValuesFromChunk()`
- Tight prompts are recommended for on-device inference
- Regular prompts can be used with cloud providers (Bedrock, OpenAI)

## Version Control

When updating prompts:
1. Save old version with descriptive suffix (e.g., `_verbose`, `_v1`, `_previous`)
2. Document changes in this README
3. Test thoroughly with representative data
4. Monitor quality metrics (accuracy, hallucinations, extraction completeness)
