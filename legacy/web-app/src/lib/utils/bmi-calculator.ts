/**
 * Calculate BMI from height and weight
 * @param height - Height value as string
 * @param heightUnit - Height unit ('cm' or 'ft')
 * @param weight - Weight value as string  
 * @param weightUnit - Weight unit ('kg' or 'lb')
 * @returns BMI value rounded to 2 decimal places, or null if invalid inputs
 */
export function calculateBMI(
  height: string | number,
  heightUnit: string,
  weight: string | number,
  weightUnit: string
): number | null {
  const heightNum = typeof height === 'string' ? parseFloat(height) : height;
  const weightNum = typeof weight === 'string' ? parseFloat(weight) : weight;

  if (isNaN(heightNum) || isNaN(weightNum) || heightNum <= 0 || weightNum <= 0) {
    return null;
  }

  // Convert height to meters
  let heightInMeters: number;
  if (heightUnit === 'cm') {
    heightInMeters = heightNum / 100;
  } else if (heightUnit === 'ft') {
    heightInMeters = heightNum * 0.3048;
  } else {
    return null; // Invalid height unit
  }

  // Convert weight to kg
  let weightInKg: number;
  if (weightUnit === 'kg') {
    weightInKg = weightNum;
  } else if (weightUnit === 'lb') {
    weightInKg = weightNum / 2.20462;
  } else {
    return null; // Invalid weight unit
  }

  // Calculate BMI: weight (kg) / height (m)²
  const bmi = weightInKg / (heightInMeters * heightInMeters);
  return Math.round(bmi * 100) / 100; // Round to 2 decimal places
}

/**
 * Get BMI category based on BMI value
 * @param bmi - BMI value
 * @returns BMI category string
 */
export function getBMICategory(bmi: number): string {
  if (bmi < 18.5) return 'Underweight';
  if (bmi < 25) return 'Normal weight';
  if (bmi < 30) return 'Overweight';
  return 'Obese';
}