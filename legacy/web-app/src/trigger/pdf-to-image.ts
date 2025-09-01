import { task } from '@trigger.dev/sdk/v3'

import sharp from 'sharp'

interface PdfToImagesPayload {
  pdfUrl: string;
}

interface PdfToImagesResult {
  images: string[];
}

export const pdfToImages = task({
  id: 'pdf-to-image',
  async run({ pdfUrl }: PdfToImagesPayload): Promise<PdfToImagesResult> {
    try {
      const response = await fetch(pdfUrl)
      if (!response.ok) {
        throw new Error(`Failed to fetch PDF: ${response.statusText}`)
      }
      
      const buffer = Buffer.from(await response.arrayBuffer())
      
      // Initialize sharp with the PDF buffer
      const pdf = sharp(buffer)
      const metadata = await pdf.metadata()
      const numPages = metadata.pages || 1
      const images: string[] = []
      
      // Loop through each page and convert to PNG
      for (let i = 0; i < numPages; i++) {
        const pageBuffer = await sharp(buffer, { page: i }).png().toBuffer()
        images.push(pageBuffer.toString('base64'))
      }
      
      return { images }
    } catch (error) {
      console.error('Error in pdfToImages task:', error)
      throw error
    }
  }
})