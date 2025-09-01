/**
 * Sync extracted vital signs data to personal info record
 * This ensures that vital signs extracted from documents update the user's trackable health metrics
 */

import prisma from "@/lib/prisma";
import { calculateBMI } from "@/lib/utils/bmi-calculator";

interface TestResult {
  value?: string | null;
  unit?: string | null;
}

interface ExtractedData {
  test_result?: {
    height?: TestResult | null;
    weight?: TestResult | null;
    bmi?: TestResult | null;
    pulse?: TestResult | null;
    blood_pressure?: TestResult | null;
    systolic_blood_pressure?: TestResult | null;
    diastolic_blood_pressure?: TestResult | null;
    oxygen_saturation?: TestResult | null;
    body_temperature?: TestResult | null;
    confidence?: number | null;
    source?: 'text' | 'image' | 'both' | null;
    [key: string]: TestResult | null | undefined | number | string;
  };
}

interface ValueUnit {
  value: string;
  unit: string;
}

interface VitalSign extends ValueUnit {
  lastUpdated: string;
}

interface PersonalInfoData {
  height?: ValueUnit;
  weight?: ValueUnit;
  vitalSigns?: {
    bmi?: VitalSign;
    pulse?: VitalSign;
    bloodPressure?: VitalSign;
    systolicBloodPressure?: VitalSign;
    diastolicBloodPressure?: VitalSign;
    oxygenSaturation?: VitalSign;
    bodyTemperature?: VitalSign;
    [key: string]: VitalSign | undefined;
  };
}

/**
 * Update personal info with extracted vital signs data
 */
export async function syncVitalSignsToPersonalInfo(
  userId: string,
  extractedData: ExtractedData
): Promise<void> {
  console.log(`[Sync] Starting vital signs sync for user ${userId}`);
  console.log(`[Sync] Extracted data:`, JSON.stringify(extractedData, null, 2));
  
  if (!extractedData.test_result) {
    console.log(`[Sync] No test_result found in extracted data, skipping sync`);
    return;
  }

  const testResult = extractedData.test_result;
  console.log(`[Sync] Test result keys:`, Object.keys(testResult));
  
  // Get or create personal info record
  let personalInfo = await prisma.healthData.findFirst({
    where: {
      authorId: userId,
      type: 'PERSONAL_INFO'
    }
  });

  if (!personalInfo) {
    personalInfo = await prisma.healthData.create({
      data: {
        type: 'PERSONAL_INFO',
        authorId: userId,
        data: {}
      }
    });
  }

  const currentData = (personalInfo.data as Partial<PersonalInfoData>) || {};
  let hasUpdates = false;

  // Update height if extracted (always update with latest value)
  if (testResult.height?.value) {
    currentData.height = {
      value: testResult.height.value,
      unit: testResult.height.unit === 'cm' ? 'cm' : 'ft'
    };
    hasUpdates = true;
    console.log(`[Sync] Updated height: ${testResult.height.value} ${testResult.height.unit}`);
  }

  // Update weight if extracted (always update with latest value)
  if (testResult.weight?.value) {
    currentData.weight = {
      value: testResult.weight.value,
      unit: testResult.weight.unit === 'kg' ? 'kg' : 'lbs'
    };
    hasUpdates = true;
    console.log(`[Sync] Updated weight: ${testResult.weight.value} ${testResult.weight.unit}`);
  }

  // Add vital signs tracking fields if they don't exist
  if (!currentData.vitalSigns) {
    currentData.vitalSigns = {};
  }

  // Calculate BMI automatically from height and weight (don't import BMI from test results)
  if (currentData.height && currentData.weight) {
    const calculatedBMI = calculateBMI(
      currentData.height.value,
      currentData.height.unit,
      currentData.weight.value,
      currentData.weight.unit
    );
    
    if (calculatedBMI !== null) {
      currentData.vitalSigns.bmi = {
        value: calculatedBMI.toString(),
        unit: 'kg/m2',
        lastUpdated: new Date().toISOString()
      };
      hasUpdates = true;
      console.log(`[Sync] Calculated BMI: ${calculatedBMI} kg/m2`);
    }
  }

  // Update pulse
  if (testResult.pulse?.value) {
    currentData.vitalSigns.pulse = {
      value: testResult.pulse.value,
      unit: testResult.pulse.unit || 'bpm',
      lastUpdated: new Date().toISOString()
    };
    hasUpdates = true;
    console.log(`[Sync] Updated pulse: ${testResult.pulse.value} bpm`);
  }

  // Update blood pressure
  if (testResult.blood_pressure?.value) {
    currentData.vitalSigns.bloodPressure = {
      value: testResult.blood_pressure.value,
      unit: testResult.blood_pressure.unit || 'mmHg',
      lastUpdated: new Date().toISOString()
    };
    hasUpdates = true;
    console.log(`[Sync] Updated blood pressure: ${testResult.blood_pressure.value}`);
  }

  // Update systolic blood pressure
  if (testResult.systolic_blood_pressure?.value) {
    currentData.vitalSigns.systolicBloodPressure = {
      value: testResult.systolic_blood_pressure.value,
      unit: testResult.systolic_blood_pressure.unit || 'mmHg',
      lastUpdated: new Date().toISOString()
    };
    hasUpdates = true;
  }

  // Update diastolic blood pressure
  if (testResult.diastolic_blood_pressure?.value) {
    currentData.vitalSigns.diastolicBloodPressure = {
      value: testResult.diastolic_blood_pressure.value,
      unit: testResult.diastolic_blood_pressure.unit || 'mmHg',
      lastUpdated: new Date().toISOString()
    };
    hasUpdates = true;
  }

  // Update oxygen saturation
  if (testResult.oxygen_saturation?.value) {
    currentData.vitalSigns.oxygenSaturation = {
      value: testResult.oxygen_saturation.value,
      unit: testResult.oxygen_saturation.unit || '%',
      lastUpdated: new Date().toISOString()
    };
    hasUpdates = true;
    console.log(`[Sync] Updated oxygen saturation: ${testResult.oxygen_saturation.value}%`);
  }

  // Update body temperature
  if (testResult.body_temperature?.value) {
    currentData.vitalSigns.bodyTemperature = {
      value: testResult.body_temperature.value,
      unit: testResult.body_temperature.unit || '°C',
      lastUpdated: new Date().toISOString()
    };
    hasUpdates = true;
    console.log(`[Sync] Updated body temperature: ${testResult.body_temperature.value}${testResult.body_temperature.unit}`);
  }

  // Save updates if any were made
  if (hasUpdates) {
    const finalData = JSON.parse(JSON.stringify(currentData));
    console.log(`[Sync] About to save Personal Info data:`, JSON.stringify(finalData, null, 2));
    
    await prisma.healthData.update({
      where: { id: personalInfo.id },
      data: { 
        data: finalData,
        updatedAt: new Date()
      }
    });
    console.log(`[Sync] Personal info updated successfully with ID: ${personalInfo.id}`);
    console.log(`[Sync] Final saved data structure:`, JSON.stringify(finalData, null, 2));
  } else {
    console.log(`[Sync] No updates needed for Personal Info`);
  }
}

/**
 * Get current vital signs from personal info
 */
export async function getCurrentVitalSigns(userId: string) {
  const personalInfo = await prisma.healthData.findFirst({
    where: {
      authorId: userId,
      type: 'PERSONAL_INFO'
    }
  });

  if (!personalInfo) {
    return null;
  }

  const data = (personalInfo.data as PersonalInfoData) || {};
  return {
    height: data.height,
    weight: data.weight,
    vitalSigns: data.vitalSigns || {}
  };
}