import Foundation

// MARK: - Validation Helper
struct ValidationHelper {
    
    // MARK: - Validation Result
    struct ValidationResult {
        let isValid: Bool
        let errorMessage: String?
        
        static let valid = ValidationResult(isValid: true, errorMessage: nil)
        
        static func invalid(_ message: String) -> ValidationResult {
            return ValidationResult(isValid: false, errorMessage: message)
        }
    }
    
    // MARK: - Name Validation
    static func validateName(_ name: String) -> ValidationResult {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedName.isEmpty {
            return .valid // Optional field
        }
        
        if trimmedName.count < 2 {
            return .invalid("Name must be at least 2 characters")
        }
        
        if trimmedName.count > 100 {
            return .invalid("Name must be less than 100 characters")
        }
        
        let allowedCharacters = CharacterSet.letters
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: ".-'"))
        
        if !trimmedName.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) {
            return .invalid("Name can only contain letters, spaces, periods, hyphens, and apostrophes")
        }
        
        return .valid
    }
    
    // MARK: - Date of Birth Validation
    static func validateDateOfBirth(_ date: Date) -> ValidationResult {
        let calendar = Calendar.current
        let now = Date()
        
        // Check if date is in the future
        if date > now {
            return .invalid("Date of birth cannot be in the future")
        }
        
        // Check if age is reasonable (0-150 years)
        let ageComponents = calendar.dateComponents([.year], from: date, to: now)
        if let age = ageComponents.year, age > 150 {
            return .invalid("Please enter a valid date of birth")
        }
        
        return .valid
    }
    
    // MARK: - Height Validation
    static func validateHeight(centimeters: Double) -> ValidationResult {
        if centimeters < 100 {
            return .invalid("Height must be at least 100 cm (3'3\")")
        }
        
        if centimeters > 220 {
            return .invalid("Height must be less than 220 cm (7'3\")")
        }
        
        return .valid
    }
    
    static func validateHeight(feet: Int, inches: Int) -> ValidationResult {
        let totalInches = Double(feet * 12 + inches)
        
        if totalInches < 36 { // 3 feet
            return .invalid("Height must be at least 3 feet")
        }
        
        if totalInches > 107 { // 8'11"
            return .invalid("Height must be less than 9 feet")
        }
        
        return .valid
    }
    
    // MARK: - Weight Validation
    static func validateWeight(kilograms: Double) -> ValidationResult {
        if kilograms < 35 {
            return .invalid("Weight must be at least 35 kg (77 lbs)")
        }
        
        if kilograms > 180 {
            return .invalid("Weight must be less than 180 kg (397 lbs)")
        }
        
        return .valid
    }
    
    static func validateWeight(pounds: Double) -> ValidationResult {
        if pounds < 80 {
            return .invalid("Weight must be at least 80 lbs")
        }
        
        if pounds > 400 {
            return .invalid("Weight must be less than 400 lbs")
        }
        
        return .valid
    }
    
    // MARK: - Blood Test Validation
    static func validateTestDate(_ date: Date) -> ValidationResult {
        let now = Date()
        
        if date > now {
            return .invalid("Test date cannot be in the future")
        }
        
        // Check if date is more than 10 years ago (reasonable limit)
        let tenYearsAgo = Calendar.current.date(byAdding: .year, value: -10, to: now) ?? Date.distantPast
        if date < tenYearsAgo {
            return .invalid("Test date seems too old. Please verify the date.")
        }
        
        return .valid
    }
    
    static func validateTestName(_ name: String) -> ValidationResult {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedName.isEmpty {
            return .invalid("Test name is required")
        }
        
        if trimmedName.count > 50 {
            return .invalid("Test name must be less than 50 characters")
        }
        
        return .valid
    }
    
    static func validateTestValue(_ value: String) -> ValidationResult {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedValue.isEmpty {
            return .invalid("Test value is required")
        }
        
        if trimmedValue.count > 20 {
            return .invalid("Value must be less than 20 characters")
        }
        
        return .valid
    }
    
    static func validateBloodTestResults(_ results: [BloodTestItem]) -> ValidationResult {
        let validResults = results.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        if validResults.isEmpty {
            return .invalid("At least one test result is required")
        }
        
        // Check for duplicate test names
        let testNames = validResults.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let uniqueNames = Set(testNames)
        if testNames.count != uniqueNames.count {
            return .invalid("Duplicate test names are not allowed")
        }
        
        // Validate individual results
        for result in validResults {
            let nameValidation = validateTestName(result.name)
            if !nameValidation.isValid {
                return nameValidation
            }
            
            let valueValidation = validateTestValue(result.value)
            if !valueValidation.isValid {
                return valueValidation
            }
        }
        
        return .valid
    }
    
    // MARK: - Email Validation (for future use)
    static func validateEmail(_ email: String) -> ValidationResult {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedEmail.isEmpty {
            return .valid // Optional field
        }
        
        let emailRegex = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        
        if !emailPredicate.evaluate(with: trimmedEmail) {
            return .invalid("Please enter a valid email address")
        }
        
        return .valid
    }
    
    // MARK: - Phone Number Validation (for future use)
    static func validatePhoneNumber(_ phoneNumber: String) -> ValidationResult {
        let trimmedPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedPhone.isEmpty {
            return .valid // Optional field
        }
        
        // Remove common formatting characters
        let digitsOnly = trimmedPhone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        if digitsOnly.count < 10 {
            return .invalid("Phone number must have at least 10 digits")
        }
        
        if digitsOnly.count > 15 {
            return .invalid("Phone number must have less than 15 digits")
        }
        
        return .valid
    }
}

// MARK: - Real-time Validation Publisher (for SwiftUI)
import Combine

extension ValidationHelper {
    
    // MARK: - Validation Publishers for Real-time Feedback
    static func nameValidationPublisher(for text: Published<String>.Publisher) -> AnyPublisher<ValidationResult, Never> {
        text
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .map { validateName($0) }
            .eraseToAnyPublisher()
    }
    
    static func testNameValidationPublisher(for text: Published<String>.Publisher) -> AnyPublisher<ValidationResult, Never> {
        text
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .map { validateTestName($0) }
            .eraseToAnyPublisher()
    }
    
    static func testValueValidationPublisher(for text: Published<String>.Publisher) -> AnyPublisher<ValidationResult, Never> {
        text
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .map { validateTestValue($0) }
            .eraseToAnyPublisher()
    }
}