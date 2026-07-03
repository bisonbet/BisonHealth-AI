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
        valid: Bool = true
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
            confidence: 0.9,
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
}
