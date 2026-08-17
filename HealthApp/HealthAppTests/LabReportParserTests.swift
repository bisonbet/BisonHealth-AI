import XCTest
import UIKit
@testable import HealthApp

final class LabReportParserTests: XCTestCase {

    private var parser: LabReportParser!

    override func setUp() {
        super.setUp()
        parser = LabReportParser()
    }

    override func tearDown() {
        parser = nil
        super.tearDown()
    }

    // MARK: - Matcher Tests

    func testMatcherExactKeyMatch() {
        let match = BloodTestResult.matchLabParameter(name: "Glucose", testType: .blood)
        XCTAssertEqual(match?.key, "glucose")
        XCTAssertEqual(match?.matchConfidence, 1.0)
    }

    func testMatcherAliasHits() {
        XCTAssertEqual(BloodTestResult.matchLabParameter(name: "HGB", testType: .blood)?.key, "hemoglobin")
        XCTAssertEqual(BloodTestResult.matchLabParameter(name: "A1C", testType: .blood)?.key, "hemoglobin_a1c")
        XCTAssertEqual(BloodTestResult.matchLabParameter(name: "HbA1c", testType: .blood)?.key, "hemoglobin_a1c")
        XCTAssertEqual(BloodTestResult.matchLabParameter(name: "White Blood Cell Count", testType: .blood)?.key, "wbc")
        XCTAssertEqual(BloodTestResult.matchLabParameter(name: "Total Cholesterol", testType: .blood)?.key, "cholesterol_total")
        XCTAssertEqual(BloodTestResult.matchLabParameter(name: "eGFR", testType: .blood)?.key, "egfr")
    }

    func testMatcherSeparatesProteinCFromCardiacCRP() {
        XCTAssertEqual(BloodTestResult.matchLabParameter(name: "Protein C", testType: .blood)?.key, "protein_c")
        XCTAssertEqual(
            BloodTestResult.matchLabParameter(name: "C-Reactive Protein, Cardiac", testType: .blood)?.key,
            "hs_crp"
        )
        XCTAssertEqual(BloodTestResult.matchLabParameter(name: "CRP Cardiac", testType: .blood)?.key, "hs_crp")
    }

    func testMatcherKeepsPercentAndAbsoluteCBCDistinct() {
        // The classic failure mode: "Neutrophils Absolute" must not match the percent parameter
        XCTAssertEqual(BloodTestResult.matchLabParameter(name: "Neutrophils", testType: .blood)?.key, "neutrophils")
        XCTAssertEqual(BloodTestResult.matchLabParameter(name: "Absolute Neutrophils", testType: .blood)?.key, "absolute_neutrophils")
        XCTAssertEqual(BloodTestResult.matchLabParameter(name: "Neutrophils Absolute", testType: .blood)?.key, "absolute_neutrophils")
        XCTAssertEqual(BloodTestResult.matchLabParameter(name: "ANC", testType: .blood)?.key, "absolute_neutrophils")
        XCTAssertEqual(BloodTestResult.matchLabParameter(name: "Lymphs", testType: .blood)?.key, "lymphocytes")
        XCTAssertEqual(BloodTestResult.matchLabParameter(name: "Abs Lymphocytes", testType: .blood)?.key, "absolute_lymphocytes")
    }

    func testMatcherUrineDisambiguation() {
        // Bare names on a urinalysis panel must map to urine parameters, not serum
        XCTAssertEqual(BloodTestResult.matchLabParameter(name: "Glucose", testType: .urine)?.key, "urine_glucose")
        XCTAssertEqual(BloodTestResult.matchLabParameter(name: "WBC", testType: .urine)?.key, "urine_wbc")
        XCTAssertEqual(BloodTestResult.matchLabParameter(name: "Specific Gravity", testType: .urine)?.key, "urine_specific_gravity")
        // And blood tests never match urine parameters
        XCTAssertEqual(BloodTestResult.matchLabParameter(name: "Glucose", testType: .blood)?.key, "glucose")
    }

    func testMatcherToleratesOCRTypos() {
        // Edit-distance fallback for OCR misreads
        XCTAssertEqual(BloodTestResult.matchLabParameter(name: "Hemglobin", testType: .blood)?.key, "hemoglobin")
        XCTAssertEqual(BloodTestResult.matchLabParameter(name: "Cholesterol Totl", testType: .blood)?.key, "cholesterol_total")
    }

    func testMatcherToleratesSpecimenAndMethodSuffixes() {
        XCTAssertEqual(
            BloodTestResult.matchLabParameter(name: "25-Hydroxyvitamin D, Serum", testType: .blood)?.key,
            "vitamin_d"
        )
        XCTAssertEqual(
            BloodTestResult.matchLabParameter(name: "Vitamin D3, Serum", testType: .blood)?.key,
            "vitamin_d"
        )
        XCTAssertEqual(
            BloodTestResult.matchLabParameter(name: "25-Hydroxyvitamin D LC/MS", testType: .blood)?.key,
            "vitamin_d"
        )
        XCTAssertEqual(
            BloodTestResult.matchLabParameter(name: "Glycohemoglobin A1c", testType: .blood)?.key,
            "hemoglobin_a1c"
        )
    }

    func testMatcherDoesNotStripSemanticallyLoadBearingWords() {
        XCTAssertEqual(
            BloodTestResult.matchLabParameter(name: "Total Protein, Serum", testType: .blood)?.key,
            "total_protein"
        )
        XCTAssertEqual(
            BloodTestResult.matchLabParameter(name: "LDL Cholesterol (Calc)", testType: .blood)?.key,
            "ldl_chol_calc"
        )
        XCTAssertEqual(
            BloodTestResult.matchLabParameter(name: "Bilirubin, Total", testType: .blood)?.key,
            "bilirubin_total"
        )
        XCTAssertEqual(
            BloodTestResult.matchLabParameter(name: "Urine Phosphate", testType: .urine)?.key,
            "urine_phosphate"
        )
    }

    func testMatcherRejectsUnknownNames() {
        XCTAssertNil(BloodTestResult.matchLabParameter(name: "Patient Name", testType: .blood))
        XCTAssertNil(BloodTestResult.matchLabParameter(name: "xy", testType: .blood))
    }

    func testNormalizeLabName() {
        XCTAssertEqual(BloodTestResult.normalizeLabName("Lipoprotein(a)"), "lipoprotein_a")
        XCTAssertEqual(BloodTestResult.normalizeLabName("  CO2 - Bicarbonate  "), "co2_bicarbonate")
        XCTAssertEqual(BloodTestResult.normalizeLabName("µIU/mL"), "uiu_ml")
    }

    // MARK: - Validator Tests

    func testValidateUnitAcceptsEquivalentNotations() {
        let wbc = BloodTestResult.standardizedLabParameters["wbc"]!
        XCTAssertTrue(BloodTestValueValidator.validateUnit("K/uL", for: wbc))
        XCTAssertTrue(BloodTestValueValidator.validateUnit("10^3/µL", for: wbc))
        XCTAssertTrue(BloodTestValueValidator.validateUnit("x10E3/uL", for: wbc))
        XCTAssertTrue(BloodTestValueValidator.validateUnit(nil, for: wbc), "Missing unit should not fail validation")
        XCTAssertFalse(BloodTestValueValidator.validateUnit("%", for: wbc))
        XCTAssertFalse(BloodTestValueValidator.validateUnit("mg/dL", for: wbc))
    }

    func testTSHAcceptsEquivalentIUUnitRepresentations() {
        guard let tsh = BloodTestResult.standardizedLabParameters["tsh"] else {
            XCTFail("Missing TSH catalog parameter")
            return
        }

        for unit in ["uIU/mL", "µIU/mL", "μIU/mL", "mIU/L"] {
            XCTAssertTrue(
                BloodTestValueValidator.validateUnit(unit, for: tsh),
                "Expected TSH unit variant to validate: \(unit)"
            )
            XCTAssertEqual(BloodTestValueValidator.canonicalUnit(unit, for: tsh), "miu/l")
        }
    }

    func testOCRUnitMismatchIsRetainedButNotImportable() {
        let candidates = parser.parse(plainText: "MCHC\t33.3\tg/aL\t31.5-35.7")
        guard let parsed = candidates.first else {
            XCTFail("Expected MCHC candidate")
            return
        }

        if case .ocrUnitMismatch = parsed.validation {
            // Expected: the value is retained for provenance and review.
        } else {
            XCTFail("Expected g/aL to be classified as an OCR unit mismatch, got \(parsed.validation)")
        }

        let review = LabCandidateReconciler.reconcile(candidates)
        XCTAssertEqual(review.needsReview.first?.candidates.first?.validationStatus, .ocrUnitMismatch)
        XCTAssertFalse(review.needsReview.first?.candidates.first?.isSelectable == true)
    }

    func testElectrolyteUnitsAreAnalyteAware() {
        for key in ["sodium", "potassium", "chloride", "co2_bicarbonate", "anion_gap"] {
            guard let parameter = BloodTestResult.standardizedLabParameters[key] else {
                XCTFail("Missing catalog parameter: \(key)")
                return
            }
            XCTAssertTrue(BloodTestValueValidator.validateUnit("mmol/L", for: parameter))
            XCTAssertTrue(BloodTestValueValidator.validateUnit("mEq/L", for: parameter))
        }

        guard let calcium = BloodTestResult.standardizedLabParameters["calcium"] else {
            XCTFail("Missing calcium catalog parameter")
            return
        }
        XCTAssertFalse(BloodTestValueValidator.validateUnit("mmol/L", for: calcium), "Unit equivalence must not be global across analytes")
    }

    func testEGFRUnitFormattingVariantsNormalize() {
        guard let egfr = BloodTestResult.standardizedLabParameters["egfr"] else {
            XCTFail("Missing eGFR catalog parameter")
            return
        }
        for unit in ["mL/min/1.73", "mL/min/1.73m2", "mL/min/1.73m²", "mL/min/1.73 m²"] {
            XCTAssertTrue(BloodTestValueValidator.validateUnit(unit, for: egfr), "Expected eGFR unit variant to validate: \(unit)")
        }
        XCTAssertFalse(BloodTestValueValidator.validateUnit("mL/min", for: egfr), "Unindexed clearance must remain distinct from eGFR")
    }

    func testDimensionlessParametersRejectReportedConcentrationUnits() {
        guard let ratio = BloodTestResult.standardizedLabParameters["bun_creatinine_ratio"] else {
            XCTFail("Missing BUN/Creatinine Ratio catalog parameter")
            return
        }
        XCTAssertTrue(BloodTestValueValidator.validateUnit(nil, for: ratio))
        XCTAssertFalse(BloodTestValueValidator.validateUnit("mg/dL", for: ratio))
    }

    func testFlagConsistency() {
        XCTAssertTrue(BloodTestValueValidator.flagConsistency(value: "250", referenceRange: "70-100", flag: "H"))
        XCTAssertTrue(BloodTestValueValidator.flagConsistency(value: "80", referenceRange: "70-100", flag: nil))
        XCTAssertTrue(BloodTestValueValidator.flagConsistency(value: "50", referenceRange: "70-100", flag: "L"))
        XCTAssertFalse(BloodTestValueValidator.flagConsistency(value: "250", referenceRange: "70-100", flag: nil))
        XCTAssertFalse(BloodTestValueValidator.flagConsistency(value: "80", referenceRange: "70-100", flag: "H"))
        // Unparseable inputs cannot be judged
        XCTAssertTrue(BloodTestValueValidator.flagConsistency(value: "Negative", referenceRange: "Negative", flag: nil))
    }

    func testQualitativeValuesAreValid() {
        let urineGlucose = BloodTestResult.standardizedLabParameters["urine_glucose"]
        let result = BloodTestValueValidator.validateValue(
            "Negative",
            testName: "Urine Glucose",
            referenceRange: "Negative",
            standardParam: urineGlucose
        )
        if case .valid = result {} else {
            XCTFail("Qualitative urinalysis value should validate, got \(result)")
        }
    }

    func testQualitativeAndBloodTypeVariantsAreValidForTheirParameters() {
        let ketones = BloodTestResult.standardizedLabParameters["urine_ketones"]
        let protein = BloodTestResult.standardizedLabParameters["urine_protein"]
        let abo = BloodTestResult.standardizedLabParameters["abo_blood_type"]

        if case .valid = BloodTestValueValidator.validateValue("Small", testName: "Urine Ketones", referenceRange: nil, standardParam: ketones) {} else {
            XCTFail("Small urine ketone result should validate")
        }
        if case .valid = BloodTestValueValidator.validateValue("1+", testName: "Urine Protein", referenceRange: nil, standardParam: protein) {} else {
            XCTFail("Semi-quantitative urine protein result should validate")
        }
        if case .valid = BloodTestValueValidator.validateValue("O+", testName: "ABO Blood Type", referenceRange: nil, standardParam: abo) {} else {
            XCTFail("ABO/Rh blood type result should validate")
        }
        if case .valid = BloodTestValueValidator.validateValue("AB positive", testName: "ABO Blood Type", referenceRange: nil, standardParam: abo) {} else {
            XCTFail("Spelled-out ABO/Rh result should validate")
        }

        let urineCulture = BloodTestResult.standardizedLabParameters["urine_culture"]
        if case .valid = BloodTestValueValidator.validateValue("No growth", testName: "Urine Culture", referenceRange: nil, standardParam: urineCulture) {} else {
            XCTFail("Urine culture's multi-word qualitative result should validate")
        }

        let urobilinogen = BloodTestResult.standardizedLabParameters["urine_urobilinogen"]
        if case .valid = BloodTestValueValidator.validateValue("Normal", testName: "Urine Urobilinogen", referenceRange: nil, standardParam: urobilinogen) {} else {
            XCTFail("Urine qualitative normal result should validate")
        }
        XCTAssertFalse(BloodTestValueValidator.isAbnormal(value: "Negative", referenceRange: "Negative", flag: nil))
        XCTAssertTrue(BloodTestValueValidator.isAbnormal(value: "Positive", referenceRange: "Negative", flag: nil))

        let serumGlucose = BloodTestResult.standardizedLabParameters["glucose"]
        if case .valid = BloodTestValueValidator.validateValue("Negative", testName: "Glucose", referenceRange: nil, standardParam: serumGlucose) {
            XCTFail("Qualitative urine values must not validate as arbitrary serum results")
        }
    }

    func testAbnormalNumericValueRemainsImportableAndIsMarkedAbnormal() {
        guard let glucose = BloodTestResult.standardizedLabParameters["glucose"] else {
            XCTFail("Missing glucose catalog parameter")
            return
        }
        let validation = BloodTestValueValidator.validateValue(
            "250",
            testName: glucose.name,
            referenceRange: "70-100",
            standardParam: glucose
        )
        if case .valid = validation {} else {
            XCTFail("Out-of-range numeric results must remain importable")
        }

        let candidate = LabValueCandidate(
            standardKey: glucose.key,
            parameter: glucose,
            originalTestName: glucose.name,
            value: "250",
            unit: "mg/dL",
            referenceRange: "70-100",
            abnormalFlag: nil,
            testType: .blood,
            source: .deterministicRow,
            pageNumber: 1,
            sourceSnippet: "Glucose 250 mg/dL 70-100",
            confidence: 0.95,
            validation: validation
        )
        let results = LabCandidateReconciler.reconcile([candidate])
        XCTAssertTrue(results.autoAccepted.isEmpty, "Abnormal values should require explicit review")
        XCTAssertEqual(results.needsReview.first?.candidates.first?.value, "250")
        XCTAssertTrue(results.needsReview.first?.candidates.first?.isAbnormal == true)
    }

    func testUrineMeasurementContextDistinguishesSpotAndTwentyFourHour() {
        guard let acr = BloodTestResult.standardizedLabParameters["urine_albumin_creatinine_ratio"],
              let calcium = BloodTestResult.standardizedLabParameters["urine_calcium"] else {
            XCTFail("Missing urine chemistry catalog parameter")
            return
        }
        let acrContext = LabMeasurementContext.infer(testName: acr.name, parameter: acr, unit: acr.unit)
        let calciumContext = LabMeasurementContext.infer(testName: calcium.name, parameter: calcium, unit: calcium.unit)

        XCTAssertEqual(acrContext.specimen, .urine)
        XCTAssertEqual(acrContext.collection, .spot)
        XCTAssertEqual(calciumContext.specimen, .urine)
        XCTAssertEqual(calciumContext.collection, .twentyFourHour)
    }

    // MARK: - Range Parsing Tests

    func testExtractRangeFormats() {
        XCTAssertEqual(parser.extractRange(from: "70-100"), "70-100")
        XCTAssertEqual(parser.extractRange(from: "3.5 - 5.0"), "3.5-5.0")
        XCTAssertEqual(parser.extractRange(from: "< 200"), "<200")
        XCTAssertEqual(parser.extractRange(from: ">40"), ">40")
        XCTAssertEqual(parser.extractRange(from: "Negative"), "Negative")
        XCTAssertNil(parser.extractRange(from: "mg/dL"))
        XCTAssertNil(parser.extractRange(from: "Glucose"))
    }

    func testTokenClassification() {
        XCTAssertTrue(parser.isValueToken("98"))
        XCTAssertTrue(parser.isValueToken("13.5"))
        XCTAssertTrue(parser.isValueToken("<0.04"))
        XCTAssertTrue(parser.isValueToken("Negative"))
        XCTAssertFalse(parser.isValueToken("Glucose"))
        XCTAssertFalse(parser.isValueToken("T3"))
        XCTAssertFalse(parser.isValueToken("70-100"))

        XCTAssertTrue(parser.isUnitToken("mg/dL"))
        XCTAssertTrue(parser.isUnitToken("µIU/mL"))
        XCTAssertTrue(parser.isUnitToken("10^3/µL"))
        XCTAssertTrue(parser.isUnitToken("%"))
        XCTAssertFalse(parser.isUnitToken("Glucose"))

        XCTAssertTrue(parser.isFlagToken("H"))
        XCTAssertTrue(parser.isFlagToken("HIGH"))
        XCTAssertTrue(parser.isFlagToken("*"))
        XCTAssertFalse(parser.isFlagToken("Hemoglobin"))
    }

    // MARK: - Plain Text Parsing (LabCorp/Quest-style layouts)

    func testParseTabDelimitedChemistryPanel() {
        let text = """
        CHEMISTRY
        Glucose\t98\tmg/dL\t70-100
        BUN\t15\tmg/dL\t7-20
        Creatinine\t0.9\tmg/dL\t0.6-1.2
        Total Cholesterol\t220\tmg/dL\t<200\tH
        """

        let candidates = parser.parse(plainText: text)
        let keys = Set(candidates.map { $0.standardKey })

        XCTAssertTrue(keys.contains("glucose"))
        XCTAssertTrue(keys.contains("bun"))
        XCTAssertTrue(keys.contains("creatinine"))
        XCTAssertTrue(keys.contains("cholesterol_total"))

        let glucose = candidates.first { $0.standardKey == "glucose" }
        XCTAssertEqual(glucose?.value, "98")
        XCTAssertEqual(glucose?.unit, "mg/dL")
        XCTAssertEqual(glucose?.referenceRange, "70-100")
        XCTAssertTrue(glucose?.isValid ?? false)
        XCTAssertEqual(glucose?.source, .deterministicRow)

        let cholesterol = candidates.first { $0.standardKey == "cholesterol_total" }
        XCTAssertEqual(cholesterol?.value, "220")
        XCTAssertEqual(cholesterol?.abnormalFlag, "H")
        XCTAssertTrue(cholesterol?.isAbnormal ?? false)
    }

    func testParseSpaceDelimitedRows() {
        let text = """
        Hemoglobin 13.5 g/dL 12.0-16.0
        Hematocrit 41 % 36-46
        """

        let candidates = parser.parse(plainText: text)
        XCTAssertEqual(candidates.count, 2)

        let hemoglobin = candidates.first { $0.standardKey == "hemoglobin" }
        XCTAssertEqual(hemoglobin?.value, "13.5")
        XCTAssertEqual(hemoglobin?.unit, "g/dL")
    }

    func testParseHandlesWrappedTestNames() {
        let text = """
        Mean Corpuscular Hemoglobin Concentration
        33.5\tg/dL\t32-36
        """

        let candidates = parser.parse(plainText: text)
        let mchc = candidates.first { $0.standardKey == "mchc" || $0.standardKey == "mean_cell_hemoglobin_concentration" }
        XCTAssertNotNil(mchc, "Wrapped test name should be joined with the following value row")
        XCTAssertEqual(mchc?.value, "33.5")
    }

    func testParseUrinalysisSectionSwitchesTestType() {
        let text = """
        URINALYSIS
        Glucose\tNegative\t\tNegative
        Protein\tTrace\t\tNegative
        """

        let candidates = parser.parse(plainText: text)

        let urineGlucose = candidates.first { $0.standardKey == "urine_glucose" }
        XCTAssertNotNil(urineGlucose, "Glucose under a urinalysis header should map to urine_glucose")
        XCTAssertEqual(urineGlucose?.value, "Negative")
        XCTAssertEqual(urineGlucose?.testType, .urine)
        XCTAssertTrue(urineGlucose?.isValid ?? false)

        let urineProtein = candidates.first { $0.standardKey == "urine_protein" }
        XCTAssertEqual(urineProtein?.value, "Trace")
    }

    func testParseSkipsHeaderRows() {
        let text = """
        Test Name\tResult\tUnits\tReference Range\tFlag
        Glucose\t98\tmg/dL\t70-100
        """

        let candidates = parser.parse(plainText: text)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.standardKey, "glucose")
    }

    func testParseIgnoresNonLabContent() {
        let text = """
        Patient: John Smith
        DOB: 01/15/1980
        Collected: 12/01/2025 08:30
        Glucose\t98\tmg/dL\t70-100
        """

        let candidates = parser.parse(plainText: text)
        XCTAssertEqual(candidates.count, 1, "Only registry-matched rows should become candidates")
        XCTAssertEqual(candidates.first?.standardKey, "glucose")
    }

    func testParseTrackspageNumbers() {
        let text = """
        Glucose\t98\tmg/dL\t70-100

        --- Page Break ---

        TSH\t2.5\tmIU/L\t0.4-4.0
        """

        let candidates = parser.parse(plainText: text)
        XCTAssertEqual(candidates.first { $0.standardKey == "glucose" }?.pageNumber, 1)
        XCTAssertEqual(candidates.first { $0.standardKey == "tsh" }?.pageNumber, 2)
    }

    // MARK: - Table Parsing (recognized structure)

    func testParseRecognizedTable() {
        let table = NativeDocumentExtractor.RecognizedTable(
            cells: [
                .init(rowIndex: 0, columnIndex: 0, text: "Test"),
                .init(rowIndex: 0, columnIndex: 1, text: "Result"),
                .init(rowIndex: 0, columnIndex: 2, text: "Reference Range"),
                .init(rowIndex: 1, columnIndex: 0, text: "Glucose"),
                .init(rowIndex: 1, columnIndex: 1, text: "98 mg/dL"),
                .init(rowIndex: 1, columnIndex: 2, text: "70-100"),
                .init(rowIndex: 2, columnIndex: 0, text: "Potassium"),
                .init(rowIndex: 2, columnIndex: 1, text: "4.2 mEq/L"),
                .init(rowIndex: 2, columnIndex: 2, text: "3.5-5.0")
            ],
            pageNumber: 1
        )
        let page = NativeDocumentExtractor.PageText(
            pageNumber: 1,
            text: "",
            observations: nil,
            tables: [table]
        )

        let candidates = parser.parse(pages: [page])
        XCTAssertEqual(candidates.count, 2, "Header row skipped, two data rows parsed")

        let glucose = candidates.first { $0.standardKey == "glucose" }
        XCTAssertEqual(glucose?.value, "98")
        XCTAssertEqual(glucose?.unit, "mg/dL")
        XCTAssertEqual(glucose?.source, .deterministicTable)
    }

    // MARK: - Reconciler Tests

    private func makeCandidate(
        key: String,
        value: String,
        unit: String? = nil,
        source: CandidateSource = .deterministicRow,
        valid: Bool = true,
        confidence: Double = 0.9
    ) -> LabValueCandidate {
        let parameter = BloodTestResult.standardizedLabParameters[key]!
        return LabValueCandidate(
            standardKey: key,
            parameter: parameter,
            originalTestName: parameter.name,
            value: value,
            unit: unit ?? parameter.unit,
            referenceRange: parameter.referenceRange,
            abnormalFlag: nil,
            testType: .blood,
            source: source,
            pageNumber: 1,
            sourceSnippet: "\(parameter.name) \(value)",
            confidence: confidence,
            validation: valid ? .valid : .invalidType(reason: "test")
        )
    }

    func testReconcilerAutoAcceptsSingleValidCandidate() {
        let results = LabCandidateReconciler.reconcile([
            makeCandidate(key: "glucose", value: "98")
        ])

        XCTAssertEqual(results.autoAccepted.count, 1)
        XCTAssertTrue(results.needsReview.isEmpty)
        XCTAssertTrue(results.autoAccepted[0].isAutoAccepted)
        XCTAssertNotNil(results.autoAccepted[0].selectedCandidateId, "Auto-accepted group must have its candidate pre-selected")
    }

    func testReconcilerRoutesSingleInvalidCandidateToReview() {
        let results = LabCandidateReconciler.reconcile([
            makeCandidate(key: "glucose", value: "9800", valid: false)
        ])

        XCTAssertTrue(results.autoAccepted.isEmpty)
        XCTAssertEqual(results.needsReview.count, 1)
        XCTAssertFalse(results.needsReview[0].isAutoAccepted)
    }

    func testReconcilerRoutesMultipleDistinctValuesToReview() {
        let results = LabCandidateReconciler.reconcile([
            makeCandidate(key: "glucose", value: "98", source: .deterministicRow),
            makeCandidate(key: "glucose", value: "89", source: .onDeviceLLM)
        ])

        XCTAssertTrue(results.autoAccepted.isEmpty)
        XCTAssertEqual(results.needsReview.count, 1)
        XCTAssertEqual(results.needsReview[0].candidates.count, 2)
        XCTAssertTrue(results.needsReview[0].hasMultipleDistinctValues)
    }

    func testReconcilerMergesCrossSourceAgreementIntoAutoAccept() {
        let results = LabCandidateReconciler.reconcile([
            makeCandidate(key: "glucose", value: "98", source: .deterministicRow),
            makeCandidate(key: "glucose", value: "98", source: .onDeviceLLM)
        ])

        XCTAssertEqual(results.autoAccepted.count, 1, "Identical values from independent passes are confirmation, not duplication")
        XCTAssertTrue(results.needsReview.isEmpty)

        let candidate = results.autoAccepted[0].candidates[0]
        XCTAssertEqual(Set(candidate.sources), Set([.deterministicRow, .onDeviceLLM]))
        XCTAssertGreaterThan(candidate.confidence, 0.9, "Cross-source agreement should boost confidence")
    }

    func testReconcilerMergesEquivalentUnitNotations() {
        let results = LabCandidateReconciler.reconcile([
            makeCandidate(key: "wbc", value: "6.4", unit: "K/uL", source: .deterministicRow),
            makeCandidate(key: "wbc", value: "6.4", unit: "10^3/µL", source: .onDeviceLLM)
        ])

        XCTAssertEqual(results.autoAccepted.count, 1, "Equivalent unit notations must merge as the same value")
        XCTAssertEqual(results.autoAccepted[0].candidates.count, 1)
    }

    func testReconcilerMergesEquivalentTSHUnits() {
        let results = LabCandidateReconciler.reconcile([
            makeCandidate(key: "tsh", value: "1.230", unit: "uIU/mL", source: .deterministicRow),
            makeCandidate(key: "tsh", value: "1.230", unit: "mIU/L", source: .onDeviceVision)
        ])

        XCTAssertEqual(results.autoAccepted.count, 1)
        XCTAssertEqual(results.autoAccepted.first?.candidates.count, 1)
    }

    func testReconcilerRoutesLowConfidenceValidSingletonToReview() {
        let results = LabCandidateReconciler.reconcile([
            makeCandidate(key: "glucose", value: "98", confidence: 0.52)
        ])

        XCTAssertTrue(results.autoAccepted.isEmpty)
        XCTAssertEqual(results.needsReview.count, 1)
        XCTAssertFalse(results.needsReview[0].isAutoAccepted)
        XCTAssertNil(results.needsReview[0].selectedCandidateId)
        XCTAssertEqual(results.needsReview[0].candidates.first?.confidence, 0.52)
    }

    func testReconcilerMergesNumericFormattingAndMissingUnit() {
        guard let parameter = BloodTestResult.standardizedLabParameters["creatinine"] else {
            XCTFail("Missing creatinine catalog parameter")
            return
        }
        let first = LabValueCandidate(
            standardKey: "creatinine",
            parameter: parameter,
            originalTestName: parameter.name,
            value: "1.13",
            unit: "mg/dL",
            referenceRange: "0.6-1.2",
            abnormalFlag: nil,
            testType: .blood,
            source: .deterministicRow,
            pageNumber: 1,
            sourceSnippet: "Creatinine 1.13 mg/dL",
            confidence: 0.9,
            validation: .valid
        )
        let second = LabValueCandidate(
            standardKey: "creatinine",
            parameter: parameter,
            originalTestName: "Creatinine",
            value: "1.130",
            unit: nil,
            referenceRange: "0.6-1.2",
            abnormalFlag: nil,
            testType: .blood,
            source: .onDeviceVision,
            pageNumber: 1,
            sourceSnippet: "Creatinine 1.130",
            confidence: 0.9,
            validation: .valid
        )

        let results = LabCandidateReconciler.reconcile([first, second])
        XCTAssertEqual(results.autoAccepted.count, 1)
        XCTAssertEqual(results.autoAccepted.first?.candidates.count, 1)
    }

    func testFuzzyNameMatchRequiresReviewEvenWhenValueIsValid() {
        let candidates = parser.parse(plainText: "Cholesterol Totl\t180\tmg/dL\t<200")
        guard let candidate = candidates.first else {
            XCTFail("Expected fuzzy cholesterol candidate")
            return
        }
        XCTAssertEqual(candidate.standardKey, "cholesterol_total")
        XCTAssertLessThan(candidate.matchConfidence, 0.7)

        let results = LabCandidateReconciler.reconcile(candidates)
        XCTAssertTrue(results.autoAccepted.isEmpty)
        XCTAssertEqual(results.needsReview.first?.standardKey, "cholesterol_total")
    }

    func testBUNCreatinineRatioDoesNotJoinCreatinineGroup() {
        let candidates = parser.parse(plainText: """
        Creatinine\t1.13\tmg/dL\t0.6-1.2
        BUN/Creatinine Ratio\t10\t\t9-20
        """)
        let results = LabCandidateReconciler.reconcile(candidates)
        let keys = Set((results.autoAccepted + results.needsReview).map(\.standardKey))
        XCTAssertEqual(keys, Set(["creatinine", "bun_creatinine_ratio"]))
    }

    func testWrongUnitRemainsExplicitlySelectableForReview() {
        let candidates = parser.parse(plainText: "Sodium\t143\tmg/dL\t134-144")
        let results = LabCandidateReconciler.reconcile(candidates)
        guard let candidate = results.needsReview.first?.candidates.first else {
            XCTFail("Expected unit-warning candidate")
            return
        }

        XCTAssertEqual(candidate.validationStatus, .unitMismatch)
        XCTAssertTrue(candidate.isSelectable)
        XCTAssertTrue(results.autoAccepted.isEmpty)
    }

    func testReconcilerHandlesMixedDocument() {
        let results = LabCandidateReconciler.reconcile([
            makeCandidate(key: "glucose", value: "98"),
            makeCandidate(key: "bun", value: "15", source: .deterministicRow),
            makeCandidate(key: "bun", value: "16", source: .onDeviceLLM),
            makeCandidate(key: "creatinine", value: "0.9", valid: false)
        ])

        XCTAssertEqual(results.autoAccepted.map { $0.standardKey }, ["glucose"])
        XCTAssertEqual(Set(results.needsReview.map { $0.standardKey }), Set(["bun", "creatinine"]))
    }

    // MARK: - End-to-End: Parse + Reconcile

    func testParseAndReconcileCleanPanelAutoAcceptsEverything() {
        let text = """
        COMPREHENSIVE METABOLIC PANEL
        Glucose\t98\tmg/dL\t70-100
        BUN\t15\tmg/dL\t7-20
        Sodium\t140\tmEq/L\t136-145
        Potassium\t4.2\tmEq/L\t3.5-5.0
        """

        let candidates = parser.parse(plainText: text)
        let results = LabCandidateReconciler.reconcile(candidates)

        XCTAssertEqual(results.autoAccepted.count, 4)
        XCTAssertTrue(results.needsReview.isEmpty, "A clean single-value panel should import silently")
    }

    func testParseAndReconcileDuplicatedValueNeedsReview() {
        // Same test appearing twice with different values (e.g. OCR misread on a summary page)
        let text = """
        Glucose\t98\tmg/dL\t70-100
        Glucose\t93\tmg/dL\t70-100
        """

        let candidates = parser.parse(plainText: text)
        let results = LabCandidateReconciler.reconcile(candidates)

        XCTAssertTrue(results.autoAccepted.isEmpty)
        XCTAssertEqual(results.needsReview.count, 1)
        XCTAssertEqual(results.needsReview[0].candidates.count, 2)
    }

    // MARK: - Cloud Vision Tier

    func testClaudeMultimodalRequestEncoding() throws {
        let contents = [
            Claude35Content(text: "Page 1:"),
            Claude35Content(jpegImageBase64: "QUJD"),
            Claude35Content(text: "Extract the values.")
        ]
        let request = Claude35Request(
            messages: [Claude35Message(role: "user", contents: contents)],
            maxTokens: 8192,
            temperature: 0.0,
            system: "extraction engine"
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let contentBlocks = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])

        XCTAssertEqual(contentBlocks.count, 3)
        XCTAssertEqual(contentBlocks[0]["type"] as? String, "text")
        XCTAssertNil(contentBlocks[0]["source"], "Text blocks must not carry a source field")

        XCTAssertEqual(contentBlocks[1]["type"] as? String, "image")
        XCTAssertNil(contentBlocks[1]["text"], "Image blocks must not carry a text field")
        let source = try XCTUnwrap(contentBlocks[1]["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "base64")
        XCTAssertEqual(source["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(source["data"] as? String, "QUJD")

        XCTAssertEqual(json["max_tokens"] as? Int, 8192)
        XCTAssertEqual(json["anthropic_version"] as? String, "bedrock-2023-05-31")
    }

    func testCloudVisionResponseParsing() {
        let response = """
        Here are the extracted values:
        ```json
        {
          "labValues": [
            {"testName": "Glucose", "testType": "BLOOD", "value": 98, "unit": "mg/dL", "referenceRange": "70-100", "flag": null, "page": 1},
            {"testName": "HGB", "testType": "BLOOD", "value": "13.5", "unit": "g/dL", "referenceRange": "12.0-16.0", "flag": null, "page": 2},
            {"testName": "Unknown Mystery Test", "testType": "BLOOD", "value": "5", "unit": null, "referenceRange": null, "flag": null, "page": 1}
          ],
          "documentDate": "2025-12-01",
          "laboratoryName": "Quest Diagnostics",
          "orderingPhysician": null
        }
        ```
        """

        let result = CloudVisionLabExtraction.parse(response)

        XCTAssertEqual(result.candidates.count, 2, "Unmatched test names are dropped; numeric JSON values are accepted")
        XCTAssertEqual(result.laboratoryName, "Quest Diagnostics")
        XCTAssertNotNil(result.documentDate)

        let glucose = result.candidates.first { $0.standardKey == "glucose" }
        XCTAssertEqual(glucose?.value, "98")
        XCTAssertEqual(glucose?.source, .cloudVision)
        XCTAssertEqual(glucose?.pageNumber, 1)

        let hemoglobin = result.candidates.first { $0.standardKey == "hemoglobin" }
        XCTAssertEqual(hemoglobin?.pageNumber, 2)
    }

    func testCloudVisionParsingToleratesGarbage() {
        XCTAssertTrue(CloudVisionLabExtraction.parse("no json here at all").candidates.isEmpty)
        XCTAssertTrue(CloudVisionLabExtraction.parse("{\"labValues\": \"not an array\"}").candidates.isEmpty)
    }

    @MainActor
    func testOnDeviceVisionFallbackRecoversPlainTextOutput() throws {
        let plainTextOutput = """
        CHEMISTRY
        Glucose\t98\tmg/dL\t70-100
        Creatinine\t0.9\tmg/dL\t0.6-1.2
        """

        let values = MLXOnDeviceClient.recoverLabValueJSON(
            fromPlainText: plainTextOutput,
            pageNumber: 2
        )
        XCTAssertEqual(values.count, 2)

        let data = try JSONSerialization.data(withJSONObject: ["labValues": values])
        let response = try XCTUnwrap(String(data: data, encoding: .utf8))
        let result = CloudVisionLabExtraction.parse(response, source: .onDeviceVision)

        let glucose = result.candidates.first { $0.standardKey == "glucose" }
        XCTAssertEqual(glucose?.value, "98")
        XCTAssertEqual(glucose?.source, .onDeviceVision)
        XCTAssertEqual(glucose?.pageNumber, 2)

        XCTAssertTrue(result.candidates.contains { $0.standardKey == "creatinine" })
    }

    func testRenderPageImagesRespectsLongEdgeLimit() throws {
        // Generate a single-page PDF in memory
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter @72dpi
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let pdfData = renderer.pdfData { context in
            context.beginPage()
            ("Glucose  98  mg/dL  70-100" as NSString).draw(
                at: CGPoint(x: 50, y: 50),
                withAttributes: [.font: UIFont.systemFont(ofSize: 14)]
            )
        }

        let extractor = NativeDocumentExtractor()
        let images = try extractor.renderPageImages(from: pdfData, fileType: .pdf)

        XCTAssertEqual(images.count, 1)
        let image = try XCTUnwrap(images.first)
        XCTAssertEqual(image.pageNumber, 1)
        XCTAssertFalse(image.jpegData.isEmpty)
        XCTAssertLessThanOrEqual(max(image.pixelWidth, image.pixelHeight), 1568)
    }

    func testLazyPageImageSourceAppliesPageLimitBeforeRendering() throws {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let pdfData = renderer.pdfData { context in
            for pageNumber in 1...3 {
                context.beginPage()
                ("Page \(pageNumber)" as NSString).draw(
                    at: CGPoint(x: 50, y: 50),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 14)]
                )
            }
        }

        let extractor = NativeDocumentExtractor()
        let source = try extractor.makePageImageSource(
            from: pdfData,
            fileType: .pdf,
            pageLimit: 1
        )

        XCTAssertEqual(source.totalPageCount, 3)
        XCTAssertEqual(source.renderedPageCount, 1)

        let firstPage = try XCTUnwrap(source.image(atPageIndex: 0))
        XCTAssertEqual(firstPage.pageNumber, 1)
        XCTAssertFalse(firstPage.jpegData.isEmpty)
        XCTAssertNil(try source.image(atPageIndex: 1))
    }
}
