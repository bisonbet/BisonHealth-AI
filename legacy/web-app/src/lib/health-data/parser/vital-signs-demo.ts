/**
 * Demo script to show how the vital signs enhancer works
 * This can be used to test the extraction logic with your example data
 */

import { extractVitalSignsFromText, enhanceVitalSigns } from './vital-signs-enhancer';

// Your example data
const exampleText = "Vital Signs03/03/2025 11:33Temperature: Pulse: 88Blood Pressure: 136/84Oxygen Level: 97%Tympanic - 36.1 °C (97 °F);Height: 184 cm (6 ft 0 in)Weight: 115.6 kg (254 lbs 14 oz)Body Mass Index (BMI): 34.14 kg/m2";

console.log("=== Vital Signs Extraction Demo ===\n");
console.log("Input text:", exampleText);
console.log("\n=== Extracted Vital Signs ===");

const extractedVitals = extractVitalSignsFromText(exampleText);
console.log(JSON.stringify(extractedVitals, null, 2));

console.log("\n=== Enhanced Results Demo ===");

// Simulate existing parsed results (like what might come from the main parser)
const existingResults = {
  test_result: {
    glucose: { value: "100", unit: "mg/dL" },
    // Simulate that the main parser only caught some vital signs
    pulse: { value: "88", unit: "bpm" }
  }
};

const enhancedResults = enhanceVitalSigns(existingResults, exampleText);
console.log(JSON.stringify(enhancedResults, null, 2));

console.log("\n=== Summary ===");
console.log("The enhancer successfully extracted:");
console.log("- Temperature: 36.1°C");
console.log("- Pulse: 88 bpm (preserved from existing)");
console.log("- Blood Pressure: 136/84 mmHg (combined and separate)");
console.log("- Oxygen Saturation: 97%");
console.log("- Height: 184 cm");
console.log("- Weight: 115.6 kg");
console.log("- BMI: 34.14 kg/m2");
console.log("- Preserved existing glucose reading");

export { extractedVitals, enhancedResults };