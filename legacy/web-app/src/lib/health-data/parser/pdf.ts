/* eslint-disable */

import { ChatPromptTemplate } from "@langchain/core/prompts";
import { HealthCheckupSchema, HealthCheckupType, ImagingReportSchema, ImagingReportType } from "@/lib/health-data/parser/schema";
import { fileTypeFromBuffer } from "file-type";
import { getFileMd5, processBatchWithConcurrency } from "@/lib/health-data/parser/util";
import { getParsePrompt, MessagePayload } from "@/lib/health-data/parser/prompt";
import visions from "@/lib/health-data/parser/vision";
import documents from "@/lib/health-data/parser/document";
import { put } from "@vercel/blob";
import { currentDeploymentEnv } from "@/lib/current-deployment-env";
import fs from "node:fs";

import { tasks } from "@trigger.dev/sdk/v3";
import type { pdfToImages } from "@/trigger/pdf-to-image";
import { exec } from "child_process";
import { promisify } from "util";
import { enhanceVitalSigns } from "@/lib/health-data/parser/vital-signs-enhancer";
import { VISION_MODEL_PREFERENCES, getFirstAvailableModel } from "@/config/model-preferences";

const execPromise = promisify(exec);

interface VisionParserOptions {
  parser: string;
  model: string;
  apiKey: string;
  apiUrl?: string;
}

interface DocumentParserOptions {
  parser: string;
  model: string;
  apiKey: string;
}

interface SourceParseOptions {
  file: string;
  visionParser?: VisionParserOptions;
  documentParser?: DocumentParserOptions;
}

interface InferenceOptions {
  imagePaths: string[];
  excludeImage: boolean;
  excludeText: boolean;
  visionParser: VisionParserOptions;
  documentParser: DocumentParserOptions;
  useClinicalPrompts?: boolean;
  useImagingPrompts?: boolean;
}

interface TestResult {
  value: string | null;
  unit: string | null;
}

function isTestResult(value: any): value is TestResult {
  return value && typeof value === 'object' && 'value' in value;
}

/**
 * Select the best available vision model from the priority list
 * @param availableModels - List of available models from the server
 * @returns The best available model ID
 */
async function selectBestVisionModel(availableModels: { id: string; name: string }[]): Promise<string> {
  try {
    // Use the centralized model selection logic
    const selectedModel = await getFirstAvailableModel(VISION_MODEL_PREFERENCES);
    
    if (selectedModel) {
      console.log(`Selected vision model: ${selectedModel.id} (priority match)`);
      return selectedModel.id;
    }

    // If no preferred model found, use the first available model
    if (availableModels.length > 0) {
      console.log(`Selected vision model: ${availableModels[0].id} (first available)`);
      return availableModels[0].id;
    }

    // Fallback to default if no models available
    console.warn('No vision models available, using default: qwen2.5vl:7b');
    return 'qwen2.5vl:7b';
  } catch (error) {
    console.error('Error selecting vision model:', error);
    return 'qwen2.5vl:7b';
  }
}

async function documentOCR({
  document,
  documentParser,
}: {
  document: string;
  documentParser: DocumentParserOptions;
}) {
  // Get the document parser
  const parser = documents.find((e) => e.name === documentParser.parser);
  if (!parser) throw new Error("Invalid document parser");

  // Get the ocr result
  const models = await parser.models();
  const model = models.find((e) => e.id === documentParser.model);
  if (!model) throw new Error("Invalid document parser model");

  // Get the ocr result
  const { ocr } = await parser.ocr({ input: document, model, apiKey: documentParser.apiKey });
  return ocr;
}

async function documentParse({
  document,
  documentParser,
}: {
  document: string;
  documentParser: DocumentParserOptions;
}): Promise<any> {
  // Get the document parser
  const parser = documents.find((e) => e.name === documentParser.parser);
  if (!parser) throw new Error("Invalid document parser");

  // Get the ocr result
  const models = await parser.models();
  const model = models.find((e) => e.id === documentParser.model);
  if (!model) throw new Error("Invalid document parser model");

  // Get the parse result
  const { document: result } = await parser.parse({ input: document, model, apiKey: documentParser.apiKey });
  return result;
}

/**
 * Document type enumeration
 */
enum DocumentType {
  LAB_RESULTS = 'lab_results',
  CLINICAL_NOTES = 'clinical_notes',
  IMAGING_REPORT = 'imaging_report'
}

/**
 * Detect the type of medical document based on OCR text
 * @param ocrText - OCR extracted text from the document
 * @returns DocumentType - the detected document type
 */
function detectDocumentType(ocrText: string): DocumentType {
  const text = ocrText.toLowerCase();

  // Imaging report keywords (highest priority)
  const imagingKeywords = [
    'radiology', 'radiologist', 'imaging', 'scan', 'study', 'medstar radiology',
    'x-ray', 'xray', 'radiograph', 'chest x-ray', 'chest xray',
    'mri', 'magnetic resonance', 'mr imaging', 'mr scan', 'mri report', 'lower back mri',
    'ct scan', 'ct', 'computed tomography', 'cat scan',
    'ultrasound', 'sonogram', 'doppler', 'echo',
    'mammography', 'mammogram', 'dexa', 'bone density',
    'pet scan', 'pet-ct', 'nuclear medicine', 'scintigraphy',
    'angiography', 'angiogram', 'arteriogram',
    'fluoroscopy', 'barium', 'contrast study',
    'findings:', 'impression:', 'technique:', 'clinical information:',
    'comparison:', 'recommendation:', 'radiologic', 'radiological',
    'axial', 'sagittal', 'coronal', 'slice', 'sequences',
    'enhancement', 'contrast', 'gadolinium', 'iodine',
    'field of view', 'fov', 'slice thickness', 'te', 'tr',
    'hounsfield', 'signal intensity', 'attenuation',
    'no acute', 'unremarkable', 'within normal limits',
    'artifact', 'motion artifact', 'beam hardening',
    'spine', 'lumbar', 'cervical', 'thoracic', 'vertebra', 'disc',
    'radiology network', 'imaging center', 'diagnostic imaging'
  ];

  // Clinical notes keywords
  const clinicalKeywords = [
    'consultation', 'visit', 'examination', 'assessment', 'diagnosis', 'treatment', 'plan',
    'chief complaint', 'history of present illness', 'physical exam',
    'discharge', 'admit', 'recommendation', 'follow-up', 'continue', 'discontinue',
    'medication', 'prescription', 'instructions', 'clinic', 'appointment',
    'symptoms', 'patient reports', 'on examination', 'appears',
    'provider', 'physician', 'doctor', 'nurse', 'clinician'
  ];

  // Lab results keywords
  const labKeywords = [
    'result', 'value', 'reference', 'range', 'normal', 'abnormal', 'high', 'low',
    'mg/dl', 'mmol/l', 'g/dl', 'mcg', 'ng/ml', 'iu/l', 'u/l',
    'complete blood count', 'cbc', 'basic metabolic', 'comprehensive metabolic',
    'lipid panel', 'thyroid', 'glucose', 'hemoglobin', 'hematocrit',
    'cholesterol', 'triglycerides', 'creatinine', 'bun'
  ];

  // Count keyword matches
  const imagingScore = imagingKeywords.filter(keyword => text.includes(keyword)).length;
  const clinicalScore = clinicalKeywords.filter(keyword => text.includes(keyword)).length;
  const labScore = labKeywords.filter(keyword => text.includes(keyword)).length;

  console.log(`[Document Detection] Imaging score: ${imagingScore}, Clinical score: ${clinicalScore}, Lab score: ${labScore}`);
  console.log(`[Document Detection] Imaging keywords found: ${imagingKeywords.filter(keyword => text.includes(keyword)).join(', ')}`);

  // Determine document type based on scores
  if (imagingScore >= 3 || (imagingScore > 0 && imagingScore >= Math.max(clinicalScore, labScore))) {
    return DocumentType.IMAGING_REPORT;
  } else if (clinicalScore > labScore || clinicalScore >= 3) {
    return DocumentType.CLINICAL_NOTES;
  } else {
    return DocumentType.LAB_RESULTS;
  }
}

/**
 * Legacy function for backward compatibility
 * @param ocrText - OCR extracted text from the document
 * @returns boolean - true if document appears to be clinical narrative
 */
function isClinicalDocument(ocrText: string): boolean {
  const docType = detectDocumentType(ocrText);
  return docType === DocumentType.CLINICAL_NOTES || docType === DocumentType.IMAGING_REPORT;
}

async function inference(inferenceOptions: InferenceOptions) {
  const {
    imagePaths,
    excludeImage,
    excludeText,
    visionParser: visionParserOptions,
    documentParser: documentParserOptions,
    useClinicalPrompts = false,
    useImagingPrompts = false,
  } = inferenceOptions;

  // Extract text data if not excluding text
  const pageDataList:
    | { page_content: string }[]
    | undefined = !excludeText
    ? await processBatchWithConcurrency(
        imagePaths,
        async (path) => {
          const { content } = await documentParse({ document: path, documentParser: documentParserOptions });
          const { markdown } = content;
          return { page_content: markdown };
        },
        2
      )
    : undefined;

  // Extract image data if not excluding images
  const imageDataList: string[] = !excludeImage
    ? await processBatchWithConcurrency(
        imagePaths,
        async (path) => {
          let buffer: Buffer;
          if (path.startsWith("http://") || path.startsWith("https://")) {
            // Handle remote URLs
            const fileResponse = await fetch(path);
            buffer = Buffer.from(await fileResponse.arrayBuffer());
          } else {
            // Handle local file paths
            buffer = fs.readFileSync(path);
          }
          return `data:image/png;base64,${buffer.toString("base64")}`;
        },
        4
      )
    : [];

  // Batch Inputs
  const numPages = pageDataList ? pageDataList.length : imageDataList.length;
  const batchInputs: MessagePayload[] = new Array(numPages).fill(0).map((_, i) => ({
    ...(!excludeText && pageDataList ? { context: pageDataList[i].page_content } : {}),
    ...(!excludeImage && imageDataList ? { image_data: imageDataList[i] } : {}),
  }));

  // Generate Messages
  const messages = ChatPromptTemplate.fromMessages(getParsePrompt({ excludeImage, excludeText, useClinicalPrompts, useImagingPrompts }));

  // Select Vision Parser
  const visionParser = visions.find((e) => e.name === visionParserOptions.parser);
  if (!visionParser) throw new Error("Invalid vision parser");

  // Get models and select the best available one
  const visionParserModels = await visionParser.models({ apiUrl: visionParserOptions.apiUrl });
  
  // Select the best available model using our priority logic
  const selectedModelId = await selectBestVisionModel(visionParserModels);
  let visionParserModel = visionParserModels.find((e) => e.id === selectedModelId);
  
  if (!visionParserModel) {
    // If the selected model isn't found, try the original requested model
    const fallbackModel = visionParserModels.find((e) => e.id === visionParserOptions.model);
    if (!fallbackModel) {
      throw new Error(`No suitable vision parser model found. Available models: ${visionParserModels.map(m => m.id).join(', ')}`);
    }
    console.warn(`Using fallback model: ${fallbackModel.id}`);
    visionParserModel = fallbackModel;
  }

  // Process the batch inputs with reduced concurrency for Ollama
  const concurrencyLimit = visionParserOptions.parser === 'Ollama' ? 1 : 4;
  const batchData = await processBatchWithConcurrency(
    batchInputs,
    async (input) =>
      visionParser.parse({
        model: visionParserModel,
        messages: messages,
        input: input,
        apiKey: visionParserOptions.apiKey,
        apiUrl: visionParserOptions.apiUrl,
      }),
    concurrencyLimit
  );

  // Merge the results
  const data: { [key: string]: any } = batchData.reduce((acc, curr, i) => {
    acc[`page_${i}`] = curr;
    return acc;
  }, {} as { [key: string]: any });

  // Handle different document types
  if (useImagingPrompts) {
    // For imaging reports, merge imaging_report data
    let mergedImagingReport: any = {};
    
    // Merge imaging report data from all pages
    for (let i = 0; i < numPages; i++) {
      const pageData = data[`page_${i}`];
      if (pageData.imaging_report) {
        // Merge non-null fields, prioritizing non-empty values
        for (const [key, value] of Object.entries(pageData.imaging_report)) {
          if (value && (!mergedImagingReport[key] || mergedImagingReport[key] === null)) {
            mergedImagingReport[key] = value;
          }
        }
      }
    }

    // Merge basic fields (name, date)
    let mergeData: any = {};
    for (let i = 0; i < numPages; i++) {
      const pageData = data[`page_${i}`];
      mergeData = {
        ...mergeData,
        ...pageData,
      };
    }

    // Set the merged imaging report
    mergeData["imaging_report"] = mergedImagingReport;

    // Create final ImagingReport object
    const finalHealthCheckup = ImagingReportSchema.parse(mergeData);
    
    return {
      finalHealthCheckup: finalHealthCheckup as any, // Type assertion for compatibility
      mergedTestResultPage: {}, // No test results for imaging reports
    };
  } else {
    // Original logic for lab results and clinical documents
    // Merge Results
    const mergeInfo: { [key: string]: { pages: number[]; values: any[] } } = {};

    for (const key of HealthCheckupSchema.shape.test_result.keyof().options) {
      const testFields = [];
      const testPages: number[] = [];
      for (let i = 0; i < numPages; i++) {
        const healthCheckup = data[`page_${i}`];
        const healthCheckupTestResult = healthCheckup.test_result;

        if (healthCheckupTestResult && healthCheckupTestResult.hasOwnProperty(key) && healthCheckupTestResult[key]) {
          testFields.push(healthCheckupTestResult[key]);
          testPages.push(i);
        }
      }

      if (testFields.length > 0) {
        mergeInfo[key] = { pages: testPages, values: testFields };
      }
    }

    const mergedTestResult: { [key: string]: any } = {};
    const mergedTestResultPage: { [key: string]: { page: number } } = {};

    // Merge the results
    for (const mergeInfoKey in mergeInfo) {
      const mergeTarget = mergeInfo[mergeInfoKey];
      mergedTestResult[mergeInfoKey] = mergeTarget.values[0];
      mergedTestResultPage[mergeInfoKey] = {
        page: mergeTarget.pages[0] + 1,
      };
    }

    let mergeData: any = {};

    // Merge name and date
    for (let i = 0; i < numPages; i++) {
      const healthCheckup = data[`page_${i}`];
      mergeData = {
        ...mergeData,
        ...healthCheckup,
      };
    }

    // Update test_result with merged data
    mergeData["test_result"] = mergedTestResult;

    // Create final HealthCheckup object
    const finalHealthCheckup = HealthCheckupSchema.parse(mergeData);
    
    return {
      finalHealthCheckup: finalHealthCheckup,
      mergedTestResultPage: mergedTestResultPage,
    };
  }
}

/**
 * Convert a document to images
 * - pdf: convert to images using an external tool (pdftoppm)
 * - image: nothing
 *
 * @param file
 *
 * @returns {Promise<string[]>} - List of image paths
 */
async function documentToImages({ file: filePath }: Pick<SourceParseOptions, "file">): Promise<string[]> {
  let fileBuffer: Buffer;
  
  if (filePath.startsWith("http://") || filePath.startsWith("https://")) {
    // Handle remote URLs
    const fileResponse = await fetch(filePath);
    fileBuffer = Buffer.from(await fileResponse.arrayBuffer());
  } else {
    // Handle local file paths
    fileBuffer = fs.readFileSync(filePath);
  }
  const result = await fileTypeFromBuffer(fileBuffer);
  const fileHash = await getFileMd5(fileBuffer);
  if (!result) throw new Error("Invalid file type");
  const mime = result.mime;

  const images: string[] = [];
  if (mime === "application/pdf") {
    if (currentDeploymentEnv === "local") {
      // Write PDF to a temporary file
      const tmpDir = "/tmp";
      const pdfFilePath = `${tmpDir}/${fileHash}.pdf`;
      fs.writeFileSync(pdfFilePath, fileBuffer);

      // Use pdftoppm to convert PDF pages to PNG images.
      // This will generate files like: /tmp/<fileHash>-1.png, /tmp/<fileHash>-2.png, etc.
      try {
        await execPromise(`pdftoppm -png "${pdfFilePath}" "${tmpDir}/${fileHash}"`);
      } catch (error) {
        throw new Error("pdftoppm conversion failed: " + error);
      }

      // Read the generated PNG files
      const tmpFiles = fs.readdirSync(tmpDir);
      const pngFiles = tmpFiles
        .filter((f) => f.startsWith(fileHash + "-") && f.endsWith(".png"))
        .sort((a, b) => {
          const pageA = parseInt(a.split("-")[1].split(".")[0]);
          const pageB = parseInt(b.split("-")[1].split(".")[0]);
          return pageA - pageB;
        });

      for (const f of pngFiles) {
        const fullPath = `${tmpDir}/${f}`;
        const imageBuffer = fs.readFileSync(fullPath);
        images.push(`data:image/png;base64,${imageBuffer.toString("base64")}`);
      }

      // Cleanup temporary files
      fs.unlinkSync(pdfFilePath);
      for (const f of pngFiles) {
        fs.unlinkSync(`${tmpDir}/${f}`);
      }
    } else {
      const result = await tasks.triggerAndPoll<typeof pdfToImages>(
        "pdf-to-image",
        { pdfUrl: filePath },
        { pollIntervalMs: 5000 }
      );
      if (result.status === "COMPLETED" && result.output) {
        images.push(...result.output.images.map((image) => `data:image/png;base64,${image}`));
      } else {
        throw new Error("Failed to convert the pdf to images");
      }
    }
  } else {
    images.push(`data:${mime};base64,${fileBuffer.toString("base64")}`);
  }

  // Write the image data to files and create public URLs
  const imagePaths = [];
  for (let i = 0; i < images.length; i++) {
    if (currentDeploymentEnv === "local") {
      const localImagePath = `./public/uploads/${fileHash}_${i}.png`;
      fs.writeFileSync(localImagePath, Buffer.from(images[i].split(",")[1], "base64"));
      imagePaths.push(localImagePath);
    } else {
      const blob = await put(
        `/uploads/${fileHash}_${i}.png`,
        Buffer.from(images[i].split(",")[1], "base64"),
        { access: "public", contentType: "image/png" }
      );
      imagePaths.push(blob.downloadUrl);
    }
  }

  return imagePaths;
}

/**
 * Parse the health data
 *
 * @param options
 */
export async function parseHealthData(options: SourceParseOptions) {
  let { file: filePath } = options;
  
  // Convert public URL to local path for processing in local environment
  if (currentDeploymentEnv === "local" && filePath.includes("/api/static/uploads/")) {
    const filename = filePath.split("/").pop();
    filePath = `./public/uploads/${filename}`;
  }

  // VisionParser
  const visionParser =
    options.visionParser || {
      parser: "Ollama",
      model: "qwen2.5vl:7b", // Default model, will be auto-selected if available
      apiKey: "",
      apiUrl: process.env.NEXT_PUBLIC_OLLAMA_URL || "http://ollama:11434",
    };

  // Document Parser
  const documentParser =
    options.documentParser || {
      parser: "Docling",
      model: "document-parse",
      apiKey: "",  // Docling doesn't require an API key
    };

  // Prepare images
  const imagePaths = await documentToImages({ file: filePath });

  // Prepare OCR results
  const ocrResults = await documentOCR({
    document: filePath,
    documentParser: documentParser,
  });

  // Detect document type using OCR text
  const ocrText = (ocrResults as { text?: string })?.text || "";
  const documentType = detectDocumentType(ocrText);
  const useClinicalPrompts = documentType === DocumentType.CLINICAL_NOTES;
  const useImagingPrompts = documentType === DocumentType.IMAGING_REPORT;
  
  console.log(`Document type detection: ${documentType} document`);
  console.log(`OCR keywords found in: ${ocrText.substring(0, 200)}...`);

  // Prepare parse results
  await processBatchWithConcurrency(
    imagePaths,
    async (path) => documentParse({ document: path, documentParser: documentParser }),
    3
  );

  // Merge the results with appropriate prompts
  const baseInferenceOptions = { imagePaths, visionParser, documentParser, useClinicalPrompts, useImagingPrompts };
  const [
    { finalHealthCheckup: resultTotal, mergedTestResultPage: resultTotalPages },
    { finalHealthCheckup: resultText, mergedTestResultPage: resultTextPages },
    { finalHealthCheckup: resultImage, mergedTestResultPage: resultImagePages },
  ] = await Promise.all([
    inference({ ...baseInferenceOptions, excludeImage: false, excludeText: false }),
    inference({ ...baseInferenceOptions, excludeImage: false, excludeText: true }),
    inference({ ...baseInferenceOptions, excludeImage: true, excludeText: false }),
  ]);

  // Enhance with vital signs extraction
  const ocrTextForVitalSigns = (ocrResults as { text?: string })?.text || "";

  // Handle different document types for final result merging
  if (useImagingPrompts) {
    // For imaging reports, return the imaging data directly without vital signs enhancement
    return { data: [resultTotal], pages: [{}], ocrResults: [ocrResults] };
  }

  // Original logic for lab results and clinical documents
  const resultDictTotal = (resultTotal as any).test_result || {};
  const resultDictText = (resultText as any).test_result || {};
  const resultDictImage = (resultImage as any).test_result || {};

  const mergedTestResult: { [key: string]: any } = {};
  const mergedPageResult: { [key: string]: { page: number } | null } = {};

  for (const key of HealthCheckupSchema.shape.test_result.keyof().options) {
    const valueTotal =
      resultDictTotal.hasOwnProperty(key) &&
      resultDictTotal[key] !== null &&
      isTestResult(resultDictTotal[key]) &&
      resultDictTotal[key].value !== null
        ? resultDictTotal[key]
        : null;
    const pageTotal = valueTotal !== null && resultTotalPages && (resultTotalPages as any)[key] ? (resultTotalPages as any)[key] : null;

    const valueText =
      resultDictText.hasOwnProperty(key) &&
      resultDictText[key] !== null &&
      isTestResult(resultDictText[key]) &&
      resultDictText[key].value !== null
        ? resultDictText[key]
        : null;
    const pageText = valueText !== null && resultTextPages && (resultTextPages as any)[key] ? (resultTextPages as any)[key] : null;

    const valueImage =
      resultDictImage.hasOwnProperty(key) &&
      resultDictImage[key] !== null &&
      isTestResult(resultDictImage[key]) &&
      resultDictImage[key].value !== null
        ? resultDictImage[key]
        : null;
    const pageImage = valueImage !== null && resultImagePages && (resultImagePages as any)[key] ? (resultImagePages as any)[key] : null;

    if (valueTotal === null) {
      if (valueText !== null) {
        mergedTestResult[key] = valueText;
        mergedPageResult[key] = pageText;
      } else if (valueImage !== null) {
        mergedTestResult[key] = valueImage;
        mergedPageResult[key] = pageImage;
      } else {
        mergedTestResult[key] = valueText;
        mergedPageResult[key] = pageText;
      }
    } else {
      mergedTestResult[key] = valueTotal;
      mergedPageResult[key] = pageTotal;
    }
  }

  // Remove all null values in mergedTestResult
  for (const key in mergedTestResult) {
    if (mergedTestResult[key] === null) {
      delete mergedTestResult[key];
    }
  }

  // Enhance with vital signs extraction for lab results
  const enhancedResult = enhanceVitalSigns({
    ...resultTotal,
    test_result: mergedTestResult,
  }, ocrTextForVitalSigns);

  const healthCheckup = HealthCheckupSchema.parse(enhancedResult);

  return { data: [healthCheckup], pages: [mergedPageResult], ocrResults: [ocrResults] };
}
