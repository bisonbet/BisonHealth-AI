import {
  BaseDocumentParser,
  DocumentModelOptions,
  DocumentOCROptions,
  DocumentParseOptions,
  DocumentParseResult,
  DocumentParserModel,
  OCRParseResult,
} from "@/lib/health-data/parser/document/base-document";

// Using native FormData
import fs from "fs";
import { currentDeploymentEnv } from "@/lib/current-deployment-env";

const DOCLING_PARAMS = {
  OCR_ENGINE: "easyocr",
  PDF_BACKEND: "dlparse_v4",
  FROM_FORMATS: ["pdf", "docx", "image"],
  FORCE_OCR: "true",
  IMAGE_EXPORT_MODE: "placeholder",
  OCR_LANG: "en",
  OCR_CONFIDENCE_THRESHOLD: "0.7",
  OCR_DPI: "300",
  OCR_PREPROCESSING: "true",
  TABLE_MODE: "accurate",
  ABORT_ON_ERROR: "false",
  RETURN_AS_FILE: "false",
  DO_OCR: "true",
};

/**
 * Represents the structure returned by docling-serve when we ask for JSON (OCR).
 * Adjust as necessary if docling-serve's schema changes.
 */
interface DoclingJsonContent {
  pages: {
    [pageNumber: string]: {
      size: {
        width: number;
        height: number;
      };
    };
  };
  texts: {
    text: string;
    prov: {
      page_no: number;
      bbox: {
        l: number;
        t: number;
        r: number;
        b: number;
      };
    }[];
  }[];
}

/**
 * The structure we'll return from `convertJsonContent`. This is an example shape
 * based on your usage in the code. Adjust as needed in your system.
 */
interface OcrResultDocument {
  metadata: {
    pages: {
      height: number;
      page: number;
      width: number;
    }[];
  };
  pages: {
    height: number;
    id: number;
    text: string;
    width: number;
    words: {
      boundingBox: {
        vertices: {
          x: number;
          y: number;
        }[];
      } | null;
      confidence: number;
      id: number;
      text: string;
    }[];
  }[];
  text?: string;
  stored: boolean;
}

export class DoclingDocumentParser extends BaseDocumentParser {
  private doclingUrl: string;

  constructor() {
    super();
    this.doclingUrl = process.env.DOCLING_URL || 'http://docling-serve:5001';
  }

  get apiKeyRequired(): boolean {
    return false;
  }

  get enabled(): boolean {
    return currentDeploymentEnv === "local";
  }

  get name(): string {
    return "Docling";
  }

  // Wrap in try/catch: if something goes wrong, return an empty model list.
  async models(_options?: DocumentModelOptions): Promise<DocumentParserModel[]> {
    void _options; // Mark as used to satisfy ESLint
    try {
      return [{ id: "document-parse", name: "Document Parse" }];
    } catch (error) {
      console.error("[Docling] Error in models:", error);
      return [];
    }
  }

  private async _performConversion(
    inputPath: string,
    toFormat: "json" | "md"
  ): Promise<{ document: { json_content?: DoclingJsonContent; md_content?: string } }> {
    // 1. Get file data
    let fileData: Buffer;
    const fileName = "defaultfile.pdf"; // Or derive from path

    if (inputPath.startsWith("http://") || inputPath.startsWith("https://")) {
      console.log(`[Docling] Detected remote URL. Downloading from: ${inputPath}`);
      const fileResponse = await fetch(inputPath);
      if (!fileResponse.ok) {
        throw new Error(
          `Failed to download remote file: ${inputPath}. Status: ${fileResponse.status}`
        );
      }
      fileData = Buffer.from(await fileResponse.arrayBuffer());
      console.log(`[Docling] Download complete. Size: ${fileData.length} bytes.`);
    } else {
      if (!fs.existsSync(inputPath)) {
        throw new Error(`File does not exist: ${inputPath}`);
      }
      const stats = fs.statSync(inputPath);
      console.log(`[Docling] Local file found. Size: ${stats.size} bytes.`);
      fileData = fs.readFileSync(inputPath);
    }

    // 2. Build form data
    const formData = new FormData();
    formData.append("ocr_engine", DOCLING_PARAMS.OCR_ENGINE);
    formData.append("pdf_backend", DOCLING_PARAMS.PDF_BACKEND);
    DOCLING_PARAMS.FROM_FORMATS.forEach(format => formData.append("from_formats", format));
    formData.append("force_ocr", DOCLING_PARAMS.FORCE_OCR);
    formData.append("image_export_mode", DOCLING_PARAMS.IMAGE_EXPORT_MODE);
    formData.append("ocr_lang", DOCLING_PARAMS.OCR_LANG);
    formData.append("ocr_confidence_threshold", DOCLING_PARAMS.OCR_CONFIDENCE_THRESHOLD);
    formData.append("ocr_dpi", DOCLING_PARAMS.OCR_DPI);
    formData.append("ocr_preprocessing", DOCLING_PARAMS.OCR_PREPROCESSING);
    formData.append("table_mode", DOCLING_PARAMS.TABLE_MODE);
    const fileBlob = new Blob([new Uint8Array(fileData)]);
    formData.append("files", fileBlob, fileName);
    formData.append("abort_on_error", DOCLING_PARAMS.ABORT_ON_ERROR);
    formData.append("to_formats", toFormat);
    formData.append("return_as_file", DOCLING_PARAMS.RETURN_AS_FILE);
    formData.append("do_ocr", DOCLING_PARAMS.DO_OCR);

    // 3. Send request
    const response = await fetch(`${this.doclingUrl}/v1alpha/convert/file`, {
      method: "POST",
      headers: {
        Accept: "application/json",
      },
      body: formData,
    });

    console.log(`[Docling] response returned with status: ${response.status} for format ${toFormat}`);

    if (!response.ok) {
      const errText = await response.text();
      throw new Error(
        `Docling server error: ${response.status} - ${response.statusText}\n${errText}`
      );
    }

    return response.json();
  }

  /**
   * OCR method. If an unexpected error happens it returns an empty OCR response.
   */
  async ocr(options: DocumentOCROptions): Promise<OCRParseResult> {
    try {
      console.log("[Docling] Starting ocr method...");
      const data = await this._performConversion(options.input, 'json');

      if (!data.document || !data.document.json_content) {
        console.error("Docling OCR response:", data);
        throw new Error("No `document.json_content` in docling-serve response");
      }
      const doclingJson = data.document.json_content as DoclingJsonContent;
      const convertedJsonContent = this.convertJsonContent(doclingJson);

      return { ocr: convertedJsonContent };
    } catch (error) {
      console.error("[Docling] Error in ocr:", error);
      // Return an empty OCR response if an error occurs.
      return { ocr: { metadata: { pages: [] }, pages: [], stored: false, text: "" } };
    }
  }

  /**
   * parse method. If an unexpected error happens it returns an empty document.
   */
  async parse(options: DocumentParseOptions): Promise<DocumentParseResult> {
    try {
      console.log("[Docling] Starting parse method...");
      const inputPath = options.input;

      let fileData: Buffer;
      const fileName = "defaultfile.pdf";

      if (inputPath.startsWith("http://") || inputPath.startsWith("https://")) {
        console.log(`[Docling] Detected remote URL. Downloading from: ${inputPath}`);
        const fileResponse = await fetch(inputPath);
        if (!fileResponse.ok) {
          throw new Error(
            `Failed to download remote file: ${inputPath}. Status: ${fileResponse.status}`
          );
        }
        fileData = Buffer.from(await fileResponse.arrayBuffer());
        console.log(`[Docling] Download complete. Size: ${fileData.length} bytes.`);
      } else {
        if (!fs.existsSync(inputPath)) {
          throw new Error(`File does not exist: ${inputPath}`);
        }
        const stats = fs.statSync(inputPath);
        console.log(`[Docling] Local file found. Size: ${stats.size} bytes.`);
        fileData = fs.readFileSync(inputPath);
      }

      // Build the multipart form data
      const formData = new FormData();
      formData.append("ocr_engine", "easyocr");
      formData.append("pdf_backend", "dlparse_v4");
      formData.append("from_formats", "pdf");
      formData.append("from_formats", "docx");
      formData.append("from_formats", "image");
      formData.append("force_ocr", "true");
      formData.append("image_export_mode", "placeholder");
      formData.append("ocr_lang", "en");
      formData.append("ocr_confidence_threshold", "0.7");  // Adjust confidence threshold
      formData.append("ocr_dpi", "300");  // Increase DPI for better quality
      formData.append("ocr_preprocessing", "true");  // Enable image preprocessing
      formData.append("table_mode", "accurate");
      const fileBlob = new Blob([new Uint8Array(fileData)]);
      formData.append("files", fileBlob, fileName);
      formData.append("abort_on_error", "false");
      formData.append("to_formats", "md");
      formData.append("return_as_file", "false");
      formData.append("do_ocr", "true");

      console.log("[Docling] FormData for parse built. Sending request now...");
      const response = await fetch(`${this.doclingUrl}/v1alpha/convert/file`, {
        method: "POST",
        headers: {
          Accept: "application/json",
        },
        body: formData,
      });

      console.log(`[Docling] parse response returned with status: ${response.status}`);

      if (!response.ok) {
        const errText = await response.text();
        throw new Error(
          `Docling server error (Parse): ${response.status} - ${response.statusText}\n${errText}`
        );
      }

      const data = await response.json();
      if (!data.document || data.document.md_content === null || data.document.md_content === undefined) {
        console.error("Docling parse response:", data);
        throw new Error("No `document.md_content` in docling-serve response");
      }
      const { md_content } = data.document;

      return { document: { content: { markdown: md_content } } };
    } catch (error) {
      console.error("[Docling] Error in parse:", error);
      // Return an empty document if an error occurs.
      return { document: { content: { markdown: "" } } };
    }
  }

  /**
   * Convert docling-serve's JSON structure into the shape we need.
   */
  private convertJsonContent(data: DoclingJsonContent): OcrResultDocument {
    try {
      const result: OcrResultDocument = {
        metadata: { pages: [] },
        pages: [],
        stored: false,
        text: ""
      };

      if (!data.pages || !data.texts) {
        console.error("Unexpected JSON content structure:", data);
        return result;
      }

      // Process each page
      for (const [pageNumStr, pageVal] of Object.entries(data.pages)) {
        const pageNum = parseInt(pageNumStr, 10);
        const pageHeight = pageVal.size.height;
        const pageWidth = pageVal.size.width;

        // Add page metadata
        result.metadata.pages.push({
          height: pageHeight,
          page: pageNum,
          width: pageWidth,
        });

        const pageObject = {
          height: pageHeight,
          id: pageNum - 1, // or just pageNum if you prefer
          text: "",
          width: pageWidth,
          words: [] as {
            boundingBox: { vertices: { x: number; y: number }[] } | null;
            confidence: number;
            id: number;
            text: string;
          }[],
        };

        let wordId = 0;
        let fullText = "";

        data.texts.forEach((textElement) => {
          textElement.prov.forEach((provItem) => {
            if (provItem.page_no === pageNum) {
              pageObject.words.push({
                boundingBox: this.convertCoordinates(provItem.bbox, pageHeight),
                confidence: 0.98,
                id: wordId++,
                text: textElement.text,
              });
              fullText += textElement.text + " ";
            }
          });
        });

        pageObject.text = fullText.trim();
        result.pages.push(pageObject);
      }

      // Combine entire doc text
      result.text = result.pages.map((p) => p.text).join("\n");
      return result;
    } catch (error) {
      console.error("[Docling] Error in convertJsonContent:", error);
      return { metadata: { pages: [] }, pages: [], stored: false, text: "" };
    }
  }

  private convertCoordinates(
    bbox: { l: number; t: number; r: number; b: number },
    pageHeight: number
  ): { vertices: { x: number; y: number }[] } | null {
    try {
      if (!bbox) return null;
      return {
        vertices: [
          { x: Math.round(bbox.l), y: Math.round(pageHeight - bbox.t) },
          { x: Math.round(bbox.r), y: Math.round(pageHeight - bbox.t) },
          { x: Math.round(bbox.r), y: Math.round(pageHeight - bbox.b) },
          { x: Math.round(bbox.l), y: Math.round(pageHeight - bbox.b) },
        ],
      };
    } catch (error) {
      console.error("[Docling] Error in convertCoordinates:", error);
      return null;
    }
  }
}
