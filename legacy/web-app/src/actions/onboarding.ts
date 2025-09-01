'use server';

import {PersonalInfoData} from "@/components/onboarding/PersonalInfo";
import prisma from "@/lib/prisma";
import {auth} from "@/auth";
import {CHAT_MODEL_PREFERENCES, getFirstAvailableModel} from "@/config/model-preferences";

/**
 * Select the best available chat model from the priority list
 * @param ollamaUrl - Ollama server URL
 * @returns The best available model ID
 */
async function selectBestChatModel(ollamaUrl: string): Promise<string> {
  try {
    // Use the centralized model selection logic
    const selectedModel = await getFirstAvailableModel(CHAT_MODEL_PREFERENCES);
    
    if (selectedModel) {
      console.log(`Selected chat model: ${selectedModel.id} (priority match)`);
      return selectedModel.id;
    }

    // If no preferred model found, fetch all models and use the first one
    const response = await fetch(`${ollamaUrl}/api/tags`);
    if (response.ok) {
      const data = await response.json() as { models: { name: string, model: string }[] };
      if (data.models.length > 0) {
        console.log(`Selected chat model: ${data.models[0].model} (first available)`);
        return data.models[0].model;
      }
    }

    // Fallback to default if no models available
    console.warn('No chat models available, using default: phi4-reasoning:14b');
    return 'phi4-reasoning:14b';
  } catch (error) {
    console.error('Error fetching models from Ollama:', error);
    return 'phi4-reasoning:14b';
  }
}

interface OnboardingSubmitRequest {
    symptoms: string;
    personalInfo: PersonalInfoData;
}

export async function onboardingSubmit(data: OnboardingSubmitRequest) {
    const session = await auth()
    const userId = session?.user?.id
    if (userId === undefined) throw new Error('User not found')

    return prisma.$transaction(async (prisma) => {
        const user = await prisma.user.findUniqueOrThrow({where: {id: userId}})
        const personalInfo = await prisma.healthData.findFirst({
            where: {authorId: userId, type: 'PERSONAL_INFO'}
        })
        const personalInfoData = {
            name: '',
            height: {unit: data.personalInfo.heightUnit, value: data.personalInfo.height},
            weight: {unit: data.personalInfo.weightUnit, value: data.personalInfo.weight},
            birthDate: data.personalInfo.birthDate,
            gender: data.personalInfo.gender,
            ethnicity: data.personalInfo.ethnicity,
            country: data.personalInfo.country,
        }
        if (personalInfo === null) {
            await prisma.healthData.create({
                data: {
                    type: 'PERSONAL_INFO',
                    authorId: userId,
                    data: personalInfoData,
                    createdAt: user.createdAt,
                    updatedAt: user.updatedAt
                }
            })
        } else {
            await prisma.healthData.update({where: {id: personalInfo.id}, data: {data: personalInfoData}})
        }

        // Save symptoms
        await prisma.healthData.create({
            data: {
                type: 'SYMPTOMS',
                authorId: userId,
                data: {description: data.symptoms}
            }
        })

        // Update onboarding status
        await prisma.user.update({where: {id: userId}, data: {hasOnboarded: true}})

        // ChatRoom assistant modes 채팅 전부 생성
        const llmProvider = await prisma.lLMProvider.findFirstOrThrow({where: {providerId: 'ollama'}})
        
        // Select the best available chat model from Ollama
        const selectedChatModel = await selectBestChatModel(llmProvider.apiURL);
        
        const assistantModes = await prisma.assistantMode.findMany({
            where: {
                OR: [
                    {authorId: userId, visibility: 'PRIVATE'},
                    {visibility: 'PUBLIC'},
                ],
                name: {in: ['Root Cause Analysis & Long Term Health.', 'Family Medicine', 'Best Doctor']}
            }
        })
        return prisma.chatRoom.createManyAndReturn({
            data: assistantModes.map((mode) => {
                return {
                    name: 'New Chat',
                    authorId: userId,
                    assistantModeId: mode.id,
                    llmProviderId: llmProvider.id,
                    llmProviderModelId: selectedChatModel
                }
            })
        })
    })
}