import {PrismaClient} from '@prisma/client'
import fs from 'fs'
import path from 'path'

const prisma = new PrismaClient()

async function main() {
    // Read the llm-provider.json file
    const llmProviderPath = path.join(process.cwd(), 'prisma', 'data', 'llm-provider.json')
    const llmProviderData = JSON.parse(fs.readFileSync(llmProviderPath, 'utf-8'))

    // Update Ollama provider with environment variable
    const ollamaProvider = llmProviderData.find((p: any) => p.providerId === 'ollama')
    if (ollamaProvider) {
        ollamaProvider.apiURL = process.env.NEXT_PUBLIC_OLLAMA_URL || 'http://ollama:11434'
    }

    // Upsert the providers
    for (const provider of llmProviderData) {
        // First try to find existing provider by providerId
        const existingProvider = await prisma.lLMProvider.findFirst({
            where: { providerId: provider.providerId }
        })

        if (existingProvider) {
            // Update existing provider
            await prisma.lLMProvider.update({
                where: { id: existingProvider.id },
                data: provider
            })
        } else {
            // Create new provider
            await prisma.lLMProvider.create({
                data: provider
            })
        }
    }
}

main()
    .then(async () => {
        await prisma.$disconnect()
    })
    .catch(async (e) => {
        console.error(e)
        await prisma.$disconnect()
        process.exit(1)
    })
