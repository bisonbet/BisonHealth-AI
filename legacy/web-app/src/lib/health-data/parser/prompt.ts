import { BaseMessagePromptTemplateLike } from "@langchain/core/prompts";

export interface MessagePayload {
    context?: string; // Parsed text
    image_data?: string; // Base64 encoded image data
}

const prompts: {
    [key: string]: BaseMessagePromptTemplateLike[]
} = {
    // <<< --- REVISED 'both' PROMPT --- >>>
    both: [
        [
            "human",
            `You are a highly precise health data analyst. Your task is to extract test results from BOTH text and image data, cross-validate them, and output them in a **strict JSON format**.

**Critical Output Format Requirements:**
1.  The entire output MUST be a single JSON object.
2.  The JSON object MUST have a single top-level key named EXACTLY \`test_result\`.
3.  The value of \`test_result\` MUST be an object.
4.  Inside \`test_result\`, EVERY key MUST be the **snake_case** name of the test. Use snake_case ONLY. Do NOT use CamelCase or Title Case.
5.  The value for each snake_case test key MUST be an object with EXACTLY two keys: \`value\` (as a string) and \`unit\` (as a string or null). For example, the structure has keys 'value' and 'unit' like in "value": "122", "unit": "mg/dL" . Do NOT use plain numbers or strings as values.
6.  If no valid results are found, \`test_result\` should be an empty object.

**Step-by-Step Extraction and Validation Process:**

Step 1: Independent Extraction
*   Analyze the provided image data. Extract all identifiable test names, their values, and units.
*   Analyze the provided parsed text ({context}). Extract all identifiable test names, their values, and units.

Step 2: Cross-Validation and Prioritization
*   Compare the results from the image and the text.
*   If the parsed text shows signs of errors (e.g., broken numbers, strange characters, nonsensical values), **prioritize the data extracted from the image** for that specific test.
*   If the image data is unclear or unreadable (e.g., blurry text, cut-off values), **prioritize the data from the parsed text** if it appears clean and correct for that specific test.
*   If both sources seem reliable but differ, use your best judgment to select the most likely correct value, prioritizing clarity and completeness.

Step 3: Handle Special Cases
*   For multi-component tests (e.g., blood pressure), create **separate snake_case keys** with their respective values formatted using the required value/unit object structure.
*   For blood pressure in "systolic/diastolic" format (e.g., "136/84"), create both a combined "blood_pressure" field and separate "systolic_blood_pressure" and "diastolic_blood_pressure" fields.
*   For vital signs data, look for temperature, pulse, oxygen saturation, height, and weight (DO NOT extract BMI - it will be calculated automatically).
*   If tests are labeled (e.g., left/right), incorporate this into the snake_case key if appropriate (e.g., \`left_vision\`, \`right_vision\`).

Step 4: Final JSON Construction
*   Consolidate the validated and prioritized results.
*   Ensure every result is placed inside the \`test_result\` object.
*   Verify that all keys inside \`test_result\` are **snake_case**.
*   Verify that all values inside \`test_result\` are objects in the required value/unit format.
*   Remove duplicate tests. If a test appears multiple times, select the single most accurate validated value.

**PDF-Specific Guidelines:**
1. For tables in PDFs, maintain the row/column structure when extracting values
2. For values split across lines, combine them correctly (e.g., "12" and "3" on separate lines should be "123")
3. For values with units in different positions, ensure proper association
4. For values with reference ranges, extract only the actual result value
5. For values with asterisks or special markers, include these in the value field

**Value Validation Rules:**
1. Blood pressure values should be in format "systolic/diastolic" (e.g., "136/84"). Also extract as separate systolic_blood_pressure and diastolic_blood_pressure fields when possible
2. Temperature values should include units (°C, °F) and method when available (e.g., "36.1", "°C")
3. Oxygen saturation should be numeric without % symbol (e.g., "97")
4. Pulse/heart rate should be numeric with "bpm" unit when available
5. Height should include units (cm, ft/in) and convert when possible
6. Weight should include units (kg, lbs) and convert when possible
7. DO NOT extract BMI - it will be calculated automatically from height and weight
8. Lab values should include appropriate units (mg/dL, mmol/L, etc.)
9. Dates should be in yyyy-mm-dd format
10. Percentages should be numeric values without the % symbol
11. Ranges should be split into separate min/max values

**Vital Signs Pattern Recognition:**
- Look for patterns like "Temperature: X°C", "Pulse: X", "Blood Pressure: X/Y", "Oxygen Level: X%", "Height: X cm", "Weight: X kg"
- Extract these even if they appear in unstructured text or mixed with other data
- Be flexible with formatting variations (spaces, colons, units in different positions)

**Final Reminder:** Adherence to the specified JSON structure (\`test_result\` key, snake_case inner keys, value/unit objects) is paramount. Double-check your final JSON output before finishing.`
        ],
        ["human", 'This is the parsed text:\n{context}'],
        ["human", [{ type: "image_url", image_url: { url: '{image_data}' } }]],
    ],

    // <<< --- REVISED 'onlyText' PROMPT --- >>>
    onlyText: [
        [
            "human",
            `As a precise health data analyst focus on accurately extracting test results from the parsed text of the health report.
Your primary goal is to output a JSON object adhering strictly to the specified format.

**Required Output Format:**
1.  The entire output MUST be a single JSON object.
2.  The JSON object MUST have a single top-level key named EXACTLY \`test_result\`.
3.  The value of \`test_result\` MUST be an object containing the extracted test results.
4.  Inside \`test_result\`, EVERY key MUST be the **snake_case** name of the test. Use snake_case ONLY.
5.  The value for each snake_case test key MUST be an object containing EXACTLY \`value\` (string) and \`unit\` (string or null) keys (e.g., having keys 'value' and 'unit' like in  "value": "122", "unit": "mg/dL" ). Do NOT use plain numbers/strings.
6.  If no results are found, \`test_result\` MUST be an empty object.

**Extraction Guidelines:**
1.  Extract only the actual test results from the text. Ignore reference ranges or irrelevant text/numbers.
2.  For multi-component tests (e.g., blood pressure), create separate **snake_case** keys with their values formatted using the required value/unit object structure.
3.  For blood pressure in "systolic/diastolic" format (e.g., "136/84"), create both a combined "blood_pressure" field and separate "systolic_blood_pressure" and "diastolic_blood_pressure" fields.
4.  Look for vital signs patterns even in unstructured text: temperature, pulse, blood pressure, oxygen saturation, height, weight (DO NOT extract BMI).
5.  Ensure results are correctly labeled (e.g., left/right) if applicable, incorporating this into the snake_case key if necessary.
6.  Avoid duplicate test keys within \`test_result\`.

**Value Validation Rules:**
1. Blood pressure values should be in format "systolic/diastolic" (e.g., "136/84"). Also extract as separate systolic_blood_pressure and diastolic_blood_pressure fields when possible
2. Temperature values should include units (°C, °F) and method when available (e.g., "36.1", "°C")
3. Oxygen saturation should be numeric without % symbol (e.g., "97")
4. Pulse/heart rate should be numeric with "bpm" unit when available
5. Height should include units (cm, ft/in) and convert when possible
6. Weight should include units (kg, lbs) and convert when possible
7. DO NOT extract BMI - it will be calculated automatically from height and weight
8. Lab values should include appropriate units (mg/dL, mmol/L, etc.)
9. Dates should be in yyyy-mm-dd format
10. Percentages should be numeric values without the % symbol
11. Ranges should be split into separate min/max values

**Vital Signs Pattern Recognition:**
- Look for patterns like "Temperature: X°C", "Pulse: X", "Blood Pressure: X/Y", "Oxygen Level: X%", "Height: X cm", "Weight: X kg"
- Extract these even if they appear in unstructured text or mixed with other data
- Be flexible with formatting variations (spaces, colons, units in different positions)

**Final Check:** Ensure the final JSON strictly follows the format described above: \`test_result\` key, **snake_case** inner keys, and value/unit objects inside.`
        ],
        ["human", 'This is the parsed text:\n{context}']
    ],

    // <<< --- REVISED 'onlyImage' PROMPT --- >>>
    onlyImage: [
        [
            "human",
            `As a precise health data analyst, your task is to accurately extract test results ONLY from the provided image data and format them into a **strict JSON structure**.

**Critical Output Format Requirements:**
1.  The entire output MUST be a single JSON object.
2.  The JSON object MUST have a single top-level key named EXACTLY \`test_result\`.
3.  The value of \`test_result\` MUST be an object.
4.  Inside \`test_result\`, EVERY key MUST be the **snake_case** name of the test. Use snake_case ONLY.
5.  The value for each snake_case test key MUST be an object with EXACTLY two keys: \`value\` (as a string) and \`unit\` (as a string or null). For example, the structure has keys 'value' and 'unit' like in "value": "122", "unit": "mg/dL" . Do NOT use plain numbers or strings as values.
6.  If no valid results are found, \`test_result\` MUST be an empty object.

**Extraction Guidelines (Image Only):**
1.  Carefully analyze the image to identify test names, values, and units. Be mindful of potential OCR inaccuracies.
2.  Extract only the actual test results. Do not extract reference ranges or other non-result text/numbers.
3.  For multi-component tests (e.g., blood pressure), create separate **snake_case** keys with their values formatted using the required value/unit object structure.
4.  For blood pressure in "systolic/diastolic" format (e.g., "136/84"), create both a combined "blood_pressure" field and separate "systolic_blood_pressure" and "diastolic_blood_pressure" fields.
5.  Look for vital signs patterns even in unstructured text: temperature, pulse, blood pressure, oxygen saturation, height, weight (DO NOT extract BMI).
6.  Ensure results are correctly labeled (e.g., left/right) if applicable, incorporating this into the snake_case key if necessary.
7.  Avoid duplicate test keys within \`test_result\`. If a test appears multiple times, select the clearest reading.

**Value Validation Rules:**
1. Blood pressure values should be in format "systolic/diastolic" (e.g., "136/84"). Also extract as separate systolic_blood_pressure and diastolic_blood_pressure fields when possible
2. Temperature values should include units (°C, °F) and method when available (e.g., "36.1", "°C")
3. Oxygen saturation should be numeric without % symbol (e.g., "97")
4. Pulse/heart rate should be numeric with "bpm" unit when available
5. Height should include units (cm, ft/in) and convert when possible
6. Weight should include units (kg, lbs) and convert when possible
7. DO NOT extract BMI - it will be calculated automatically from height and weight
8. Lab values should include appropriate units (mg/dL, mmol/L, etc.)
9. Dates should be in yyyy-mm-dd format
10. Percentages should be numeric values without the % symbol
11. Ranges should be split into separate min/max values

**Vital Signs Pattern Recognition:**
- Look for patterns like "Temperature: X°C", "Pulse: X", "Blood Pressure: X/Y", "Oxygen Level: X%", "Height: X cm", "Weight: X kg"
- Extract these even if they appear in unstructured text or mixed with other data
- Be flexible with formatting variations (spaces, colons, units in different positions)

**Final Check:** Ensure the final JSON strictly follows the format described: \`test_result\` key, **snake_case** inner keys, and value/unit objects inside.`
        ],
        ["human", [{ type: "image_url", image_url: { url: '{image_data}' } }]],
    ],

    // Clinical document prompts for narrative medical records
    clinicalBoth: [
        [
            "human",
            `You are a medical records analyst specializing in extracting structured information from clinical documents. Your task is to analyze BOTH text and image data to extract clinical information and output it in a **strict JSON format**.

**Critical Output Format Requirements:**
1. The entire output MUST be a single JSON object.
2. The JSON object MUST have TWO top-level keys: \`test_result\` and \`clinical_data\`.
3. \`test_result\` should contain any structured lab values/vital signs found (using the same format as before).
4. \`clinical_data\` should contain the clinical narrative information extracted from the document.
5. Both sections can be populated if the document contains both types of data.
6. If no clinical data is found, \`clinical_data\` should be null.
7. If no test results are found, \`test_result\` should be an empty object.

**Clinical Data Extraction Guidelines:**
Extract the following clinical information when available:
- Document type (consultation note, discharge summary, imaging report, etc.)
- Patient and provider information
- Visit date and institution
- Chief complaint and reason for visit
- History of present illness
- Physical examination findings
- Clinical assessment and diagnosis
- Treatment plan and medications
- Follow-up instructions
- Imaging findings and lab orders
- Procedures performed
- Vital signs mentioned in narrative
- Allergies, medical history, social history
- Review of systems
- Clinical notes and observations
- Discharge instructions and return precautions
- Clinical summary

**Step-by-Step Process:**
1. First, scan for any structured test results (lab values, vital signs) and extract them to \`test_result\`
2. Then, analyze the document for clinical narrative content and extract to \`clinical_data\`
3. Cross-validate information between text and image sources
4. Prioritize clear, complete information over partial or unclear data
5. Use medical terminology accurately and preserve clinical context

**Final Output:** Return a JSON object with "test_result" and "clinical_data" keys.`
        ],
        ["human", 'This is the parsed text:\n{context}'],
        ["human", [{ type: "image_url", image_url: { url: '{image_data}' } }]],
    ],

    clinicalText: [
        [
            "human",
            `As a medical records analyst, extract both structured test results and clinical information from the provided medical document text.

**Required Output Format:**
1. The entire output MUST be a single JSON object.
2. The JSON object MUST have TWO top-level keys: \`test_result\` and \`clinical_data\`.
3. \`test_result\` should contain structured lab values/vital signs (snake_case keys with value/unit objects).
4. \`clinical_data\` should contain clinical narrative information.
5. If no clinical data is found, \`clinical_data\` should be null.
6. If no test results are found, \`test_result\` should be an empty object.

**Clinical Data Fields to Extract:**
- document_type: Type of clinical document
- patient_name: Patient name
- provider_name: Healthcare provider name
- institution: Healthcare institution/clinic
- visit_date: Date of visit (yyyy-mm-dd format)
- chief_complaint: Main reason for visit
- history_present_illness: Current illness history
- physical_examination: Physical exam findings
- assessment: Clinical assessment
- diagnosis: Primary and secondary diagnoses
- treatment_plan: Treatment recommendations
- medications: Prescribed medications
- follow_up: Follow-up instructions
- imaging_findings: Imaging results
- lab_orders: Laboratory tests ordered
- procedures: Procedures performed
- vital_signs_narrative: Vital signs in narrative form
- allergies_mentioned: Allergies mentioned
- medical_history_mentioned: Relevant medical history
- social_history: Social history (smoking, alcohol, etc.)
- family_history: Family history mentioned
- review_of_systems: Review of systems
- clinical_notes: Additional clinical observations
- discharge_instructions: Discharge instructions
- return_precautions: When to return for care
- summary: Clinical summary

**Extract both test results AND clinical narrative data when present.**`
        ],
        ["human", 'This is the parsed text:\n{context}']
    ],

    clinicalImage: [
        [
            "human",
            `As a medical records analyst, extract both structured test results and clinical information from the provided medical document image.

**Critical Output Format Requirements:**
1. The entire output MUST be a single JSON object.
2. The JSON object MUST have TWO top-level keys: \`test_result\` and \`clinical_data\`.
3. \`test_result\` should contain structured lab values/vital signs (snake_case keys with value/unit objects).
4. \`clinical_data\` should contain clinical narrative information extracted from the image.
5. If no clinical data is found, \`clinical_data\` should be null.
6. If no test results are found, \`test_result\` should be an empty object.

**From the image, extract:**
- Any structured lab values or vital signs → \`test_result\`
- Clinical narrative information → \`clinical_data\` (using the same fields as text extraction)
- Patient demographics and visit information
- Clinical assessments, diagnoses, and treatment plans
- Provider notes and recommendations
- Any medical observations or findings

**Be careful with OCR accuracy and prioritize clear, readable information.**`
        ],
        ["human", [{ type: "image_url", image_url: { url: '{image_data}' } }]],
    ],

    // Imaging report prompts for radiology reports (X-ray, MRI, CT, etc.)
    imagingBoth: [
        [
            "human",
            `You are a specialized medical imaging analyst. Your task is to extract structured information from medical imaging reports (X-ray, MRI, CT, Ultrasound, etc.) using BOTH text and image data. Output the information in a **strict JSON format**.

**Critical Output Format Requirements:**
1. The entire output MUST be a single JSON object.
2. The JSON object MUST have a single top-level key named EXACTLY \`imaging_report\`.
3. The value of \`imaging_report\` MUST be an object containing the structured imaging data.
4. Use the exact field names specified below (snake_case format).
5. If a field is not found, set it to null.
6. DO NOT extract lab values, vital signs, or blood pressure - this is an imaging report, not lab results.
7. Focus ONLY on radiological findings, impressions, and imaging-specific information.

**Required Imaging Report Fields:**
- exam_type: Type of imaging study (X-ray, MRI, CT, Ultrasound, etc.)
- body_part: Body part or region examined
- exam_date: Date of examination (yyyy-mm-dd format)
- clinical_information: Clinical history, symptoms, reason for exam
- clinical_indication: Medical indication or reason for the study
- technique: Technical parameters, contrast used, sequences, etc.
- contrast: Contrast agent used (if any)
- findings: Detailed radiological findings and observations
- bones: Bone-related findings
- joints: Joint-related findings
- soft_tissues: Soft tissue findings
- organs: Organ-specific findings
- vessels: Vascular findings
- measurements: Any measurements taken during the study
- dimensions: Size measurements of structures or abnormalities
- impression: Radiologist's impression or conclusion
- diagnosis: Primary diagnosis or differential diagnoses
- recommendations: Follow-up recommendations or additional studies needed
- follow_up: Suggested follow-up timeline or actions
- comparison: Comparison with previous studies
- prior_studies: Reference to previous imaging studies
- limitations: Study limitations or technical issues
- quality: Image quality assessment
- artifacts: Imaging artifacts noted
- cardiovascular: Heart and vascular findings
- pulmonary: Lung and respiratory findings
- gastrointestinal: GI tract findings
- genitourinary: Kidney, bladder, reproductive organ findings
- neurological: Brain, spine, nerve findings
- musculoskeletal: Bone, joint, muscle findings
- severity: Severity assessment of findings
- urgency: Urgency level or critical findings
- notes: Additional notes or comments
- radiologist: Reporting radiologist name

**Extraction Guidelines:**
1. This is a RADIOLOGY/IMAGING REPORT - do NOT extract lab values, vital signs, or blood pressure
2. Cross-validate information between text and image sources
3. Prioritize clear, complete information over partial data
4. Preserve medical terminology and clinical context
5. Extract measurements with appropriate units (sizes, dimensions of anatomical structures)
6. Identify and categorize findings by anatomical system
7. Distinguish between normal and abnormal findings
8. Extract recommendations and follow-up instructions
9. Note any technical limitations or artifacts
10. Focus on radiological findings, not patient vital signs or lab results

**Final Output:** Return a JSON object with the "imaging_report" key containing all extracted fields.`
        ],
        ["human", 'This is the parsed text:\n{context}'],
        ["human", [{ type: "image_url", image_url: { url: '{image_data}' } }]],
    ],

    imagingText: [
        [
            "human",
            `As a medical imaging analyst, extract structured information from the provided imaging report text.

**Required Output Format:**
1. The entire output MUST be a single JSON object.
2. The JSON object MUST have a single top-level key named EXACTLY \`imaging_report\`.
3. Extract all relevant imaging report fields as specified.
4. Use snake_case field names and set missing fields to null.
5. DO NOT extract lab values, vital signs, or blood pressure from imaging reports.
6. Focus ONLY on radiological findings and imaging-specific information.

**Key Fields to Extract:**
- Basic information: exam_type, body_part, exam_date
- Clinical context: clinical_information, clinical_indication
- Technical details: technique, contrast
- Findings: findings, impression, diagnosis
- Anatomical findings: bones, joints, soft_tissues, organs, vessels
- System-specific findings: cardiovascular, pulmonary, gastrointestinal, genitourinary, neurological, musculoskeletal
- Measurements: measurements, dimensions
- Recommendations: recommendations, follow_up
- Comparison: comparison, prior_studies
- Quality: quality, artifacts, limitations
- Additional: severity, urgency, notes, radiologist

**Focus on extracting the radiologist's findings, impressions, and recommendations accurately.**`
        ],
        ["human", 'This is the parsed text:\n{context}']
    ],

    imagingImage: [
        [
            "human",
            `As a medical imaging analyst, extract structured information from the provided imaging report image.

**Critical Output Format Requirements:**
1. The entire output MUST be a single JSON object.
2. The JSON object MUST have a single top-level key named EXACTLY \`imaging_report\`.
3. Extract imaging report fields from the image, being careful with OCR accuracy.
4. Use snake_case field names and set missing fields to null.
5. DO NOT extract lab values, vital signs, or blood pressure from imaging reports.
6. This is a RADIOLOGY REPORT - focus on imaging findings only.

**Extract from the image:**
- Document header information (exam type, date, patient info)
- Clinical indication and history
- Technical parameters and contrast information
- Detailed findings and observations
- Radiologist's impression and diagnosis
- Recommendations and follow-up instructions
- Measurements and dimensions
- Comparison with prior studies
- Quality assessments and limitations

**Be especially careful with:**
- Medical terminology and abbreviations
- Numerical measurements and their units
- Anatomical references and locations
- Normal vs. abnormal findings
- Critical or urgent findings

**Prioritize clear, readable information and preserve medical context.**`
        ],
        ["human", [{ type: "image_url", image_url: { url: '{image_data}' } }]],
    ]
};

/**
 * Get the appropriate prompt based on the input type and document type
 *
 * @param excludeImage
 * @param excludeText
 * @param useClinicalPrompts - Whether to use clinical document prompts
 * @param useImagingPrompts - Whether to use imaging report prompts
 */
export function getParsePrompt({ excludeImage, excludeText, useClinicalPrompts = false, useImagingPrompts = false }: {
    excludeImage: boolean,
    excludeText: boolean,
    useClinicalPrompts?: boolean,
    useImagingPrompts?: boolean
}): BaseMessagePromptTemplateLike[] {
    // Determine which prompt set to use based on document type
    let promptPrefix = '';
    if (useImagingPrompts) {
        promptPrefix = 'imaging';
    } else if (useClinicalPrompts) {
        promptPrefix = 'clinical';
    }

    if (!excludeImage && !excludeText) {
        return prompts[promptPrefix ? `${promptPrefix}Both` : 'both'];
    } else if (excludeImage && !excludeText) {
        return prompts[promptPrefix ? `${promptPrefix}Text` : 'onlyText'];
    } else if (!excludeImage && excludeText) {
        return prompts[promptPrefix ? `${promptPrefix}Image` : 'onlyImage'];
    } else {
        throw new Error('Invalid prompt type');
    }
}
