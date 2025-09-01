/**
 * Enhanced vital signs extraction and processing
 * This module provides additional processing for vital signs data that might be missed
 * by the main parsing logic or needs format conversion.
 */

interface TestResult {
  value: string | null;
  unit: string | null;
}

interface VitalSignsData {
  [key: string]: TestResult;
}

/**
 * Extract vital signs from unstructured text using pattern matching
 */
export function extractVitalSignsFromText(text: string): VitalSignsData {
  const results: VitalSignsData = {};
  
  // Temperature patterns
  const tempPatterns = [
    /temperature[:\s]*([0-9]+\.?[0-9]*)\s*°?([CF])?/gi,
    /temp[:\s]*([0-9]+\.?[0-9]*)\s*°?([CF])?/gi,
    /tympanic[:\s-]*([0-9]+\.?[0-9]*)\s*°([CF])/gi,
    /([0-9]+\.?[0-9]*)\s*°([CF])/g
  ];
  
  for (const pattern of tempPatterns) {
    const matches = text.matchAll(pattern);
    for (const match of matches) {
      if (match[1] && !results.body_temperature) {
        results.body_temperature = {
          value: match[1],
          unit: match[2] ? `°${match[2].toUpperCase()}` : "°C"
        };
        break;
      }
    }
  }
  
  // Pulse patterns
  const pulsePatterns = [
    /pulse[:\s]*([0-9]+)/gi,
    /heart\s*rate[:\s]*([0-9]+)/gi,
    /hr[:\s]*([0-9]+)/gi
  ];
  
  for (const pattern of pulsePatterns) {
    const matches = text.matchAll(pattern);
    for (const match of matches) {
      if (match[1] && !results.pulse) {
        results.pulse = {
          value: match[1],
          unit: "bpm"
        };
        break;
      }
    }
  }
  
  // Blood pressure patterns
  const bpPatterns = [
    /blood\s*pressure[:\s]*([0-9]+)\/([0-9]+)/gi,
    /bp[:\s]*([0-9]+)\/([0-9]+)/gi,
    /([0-9]+)\/([0-9]+)(?=\s*mmhg|\s*$|\s*[^0-9])/gi
  ];
  
  for (const pattern of bpPatterns) {
    const matches = text.matchAll(pattern);
    for (const match of matches) {
      if (match[1] && match[2]) {
        // Combined blood pressure
        if (!results.blood_pressure) {
          results.blood_pressure = {
            value: `${match[1]}/${match[2]}`,
            unit: "mmHg"
          };
        }
        
        // Separate systolic and diastolic
        if (!results.systolic_blood_pressure) {
          results.systolic_blood_pressure = {
            value: match[1],
            unit: "mmHg"
          };
        }
        
        if (!results.diastolic_blood_pressure) {
          results.diastolic_blood_pressure = {
            value: match[2],
            unit: "mmHg"
          };
        }
        break;
      }
    }
  }
  
  // Oxygen saturation patterns
  const oxygenPatterns = [
    /oxygen\s*(?:level|saturation)[:\s]*([0-9]+)%?/gi,
    /o2\s*(?:sat|saturation)[:\s]*([0-9]+)%?/gi,
    /spo2[:\s]*([0-9]+)%?/gi,
    /([0-9]+)%(?=\s*oxygen|\s*o2|\s*sat)/gi
  ];
  
  for (const pattern of oxygenPatterns) {
    const matches = text.matchAll(pattern);
    for (const match of matches) {
      if (match[1] && !results.oxygen_saturation) {
        results.oxygen_saturation = {
          value: match[1],
          unit: "%"
        };
        break;
      }
    }
  }
  
  // Height patterns
  const heightPatterns = [
    /height[:\s]*([0-9]+\.?[0-9]*)\s*(cm|centimeters?)/gi,
    /height[:\s]*([0-9]+)\s*ft\s*([0-9]+)\s*in/gi,
    /([0-9]+\.?[0-9]*)\s*cm(?=\s*\(|\s*$|\s*[^a-z])/gi
  ];
  
  for (const pattern of heightPatterns) {
    const matches = text.matchAll(pattern);
    for (const match of matches) {
      if (match[1] && !results.height) {
        if (match[2] && match[2].toLowerCase().includes('ft')) {
          // Convert feet/inches to cm
          const feet = parseInt(match[1]);
          const inches = match[2] ? parseInt(match[2]) : 0;
          const totalCm = (feet * 12 + inches) * 2.54;
          results.height = {
            value: totalCm.toFixed(1),
            unit: "cm"
          };
        } else {
          results.height = {
            value: match[1],
            unit: match[2] || "cm"
          };
        }
        break;
      }
    }
  }
  
  // Weight patterns
  const weightPatterns = [
    /weight[:\s]*([0-9]+\.?[0-9]*)\s*(kg|kilograms?)/gi,
    /weight[:\s]*([0-9]+\.?[0-9]*)\s*(lbs?|pounds?)/gi,
    /([0-9]+\.?[0-9]*)\s*kg(?=\s*\(|\s*$|\s*[^a-z])/gi,
    /([0-9]+\.?[0-9]*)\s*lbs?(?=\s*$|\s*[^a-z])/gi
  ];
  
  for (const pattern of weightPatterns) {
    const matches = text.matchAll(pattern);
    for (const match of matches) {
      if (match[1] && !results.weight) {
        let value = match[1];
        let unit = match[2] || "kg";
        
        // Convert lbs to kg if needed
        if (unit.toLowerCase().includes('lb')) {
          value = (parseFloat(value) * 0.453592).toFixed(1);
          unit = "kg";
        }
        
        results.weight = {
          value: value,
          unit: unit
        };
        break;
      }
    }
  }
  
  // BMI is calculated automatically from height and weight, don't extract from text
  
  return results;
}

interface ParsedResults {
  test_result?: { [key: string]: TestResult };
  [key: string]: unknown;
}

/**
 * Enhance parsed results by adding missing vital signs and converting formats
 */
export function enhanceVitalSigns(
  parsedResults: ParsedResults,
  originalText: string
): ParsedResults {
  if (!parsedResults.test_result) {
    parsedResults.test_result = {};
  }
  
  // Extract additional vital signs from text
  const extractedVitals = extractVitalSignsFromText(originalText);
  
  // Add missing vital signs
  for (const [key, value] of Object.entries(extractedVitals)) {
    if (!parsedResults.test_result[key]) {
      parsedResults.test_result[key] = value;
    }
  }
  
  // Handle blood pressure format conversion
  const testResult = parsedResults.test_result;
  
  // If we have combined blood pressure but not separate values
  if (testResult.blood_pressure && testResult.blood_pressure.value) {
    const bpMatch = testResult.blood_pressure.value.match(/([0-9]+)\/([0-9]+)/);
    if (bpMatch) {
      if (!testResult.systolic_blood_pressure) {
        testResult.systolic_blood_pressure = {
          value: bpMatch[1],
          unit: "mmHg"
        };
      }
      if (!testResult.diastolic_blood_pressure) {
        testResult.diastolic_blood_pressure = {
          value: bpMatch[2],
          unit: "mmHg"
        };
      }
    }
  }
  
  // If we have separate values but not combined
  if (testResult.systolic_blood_pressure && testResult.diastolic_blood_pressure && !testResult.blood_pressure) {
    const systolic = testResult.systolic_blood_pressure.value;
    const diastolic = testResult.diastolic_blood_pressure.value;
    if (systolic && diastolic) {
      testResult.blood_pressure = {
        value: `${systolic}/${diastolic}`,
        unit: "mmHg"
      };
    }
  }
  
  return parsedResults;
}