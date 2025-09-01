import {DoclingDocumentParser} from "@/lib/health-data/parser/document/docling";

const documents = [
    new DoclingDocumentParser(),
].filter(d => d.enabled)

export default documents
