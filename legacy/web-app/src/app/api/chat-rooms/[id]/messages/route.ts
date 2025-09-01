import {NextRequest, NextResponse} from "next/server";
import prisma, {Prisma} from "@/lib/prisma";
import {auth} from "@/auth";

export const runtime = 'nodejs';

export interface ChatMessage extends Prisma.ChatMessageGetPayload<{
    select: {
        id: true,
        content: true,
        createdAt: true,
        role: true
    }
}> {
    id: string,
}

export interface ChatMessageListResponse {
    chatMessages: ChatMessage[]
}

export interface ChatMessageCreateRequest {
    content: string,
    role: 'USER' | 'ASSISTANT',
    settings?: {
        company: string,
        model: string,
        apiEndpoint: string,
        apiKey: string
    }
}

interface LLMProvider {
    id: string;
    providerId: string;
    apiURL: string;
}

export async function GET(
    req: NextRequest,
    {params}: { params: Promise<{ id: string }> }
) {
    const {id} = await params
    const chatMessages = await prisma.chatMessage.findMany({
        where: {chatRoomId: id},
        orderBy: {createdAt: 'asc'}
    });

    return NextResponse.json<ChatMessageListResponse>({chatMessages})
}

async function generateChatTitle(messages: { role: string; content: string }[], llmProvider: LLMProvider, modelId: string) {
    // Only generate title if this is the first exchange
    if (messages.length !== 3) return null; // system prompt + health data + first user message

    const titlePrompt = `You are a title generator. Your task is to create a concise title for a chat conversation based on the user's first message.

IMPORTANT RULES:
1. Generate ONLY the title, nothing else
2. Do not include any thinking process or explanations
3. Do not use markdown or any special formatting
4. Do not include any tags or brackets
5. Title must be 20-30 characters long
6. Title should be a concise summary, not a question
7. Focus on the main topic or concern
8. Use clear, simple language

User's message: ${messages[2].content}

Generate the title now:`;

    try {
        const ollamaApiUrl = process.env.NEXT_PUBLIC_OLLAMA_URL || "http://ollama:11434";
        
        const response = await fetch(`${ollamaApiUrl}/api/chat`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                model: modelId,
                messages: [{
                    role: "user",
                    content: titlePrompt
                }],
                stream: false,
            }),
        });

        if (!response.ok) {
            const errorText = await response.text();
            console.error('Ollama API error:', {
                status: response.status,
                statusText: response.statusText,
                error: errorText,
                model: modelId
            });
            throw new Error(`Ollama API error: ${response.status} ${response.statusText}`);
        }

        const data = await response.json();

        if (!data.message?.content) {
            console.error('Invalid response format:', data);
            throw new Error('Invalid response format from Ollama API');
        }

        // Clean up the response to get only the title
        let title = data.message.content.trim();
        
        // Remove any thinking process or tags
        title = title.replace(/<think>[\s\S]*?<\/think>/g, '').trim();
        title = title.replace(/^["']|["']$/g, '').trim(); // Remove quotes if present
        
        // Take only the first line if multiple lines
        title = title.split('\n')[0].trim();
        
        if (!title) {
            console.error('Empty title generated');
            throw new Error('Empty title generated');
        }

        return title;
    } catch (error) {
        console.error('Error generating chat title:', error);
        return null;
    }
}

export async function POST(
    req: NextRequest,
    {params}: {
        params: Promise<{ id: string }>,
    }
) {
    const session = await auth()
    const user = session?.user
    if (!session || !user) return NextResponse.json({error: 'Unauthorized'}, {status: 401})

    const {id} = await params
    const body: ChatMessageCreateRequest = await req.json()

    const {
        chatRoom,
        assistantMode,
        chatMessages,
        healthDataList
    } = await prisma.$transaction(async (prisma) => {
        await prisma.chatMessage.create({data: {content: body.content, role: body.role, chatRoomId: id}});
        const {assistantMode} = await prisma.chatRoom.update({
            where: {id},
            data: {lastActivityAt: new Date()},
            select: {assistantMode: {select: {systemPrompt: true}}}
        })
        const chatMessages = await prisma.chatMessage.findMany({
            where: {chatRoomId: id},
            orderBy: {createdAt: 'asc'}
        })
        const healthDataList = await prisma.healthData.findMany({where: {authorId: user.id}})
        const chatRoom = await prisma.chatRoom.findUniqueOrThrow({
            where: {id},
            include: {
                assistantMode: true,
                llmProvider: true
            }
        });
        return {
            chatRoom,
            chatMessages,
            assistantMode,
            healthDataList
        }
    }, {
        timeout: 30000 // Increase timeout to 30 seconds
    })

    const messages = [
        {"role": "system" as const, "content": assistantMode.systemPrompt},
        {
            "role": "user" as const,
            "content": `Health data sources: ${healthDataList.map((healthData) => `${healthData.type}: ${JSON.stringify(healthData.data)}`).join('\n')}`
        },
        ...chatMessages.map((message) => ({
            role: message.role.toLowerCase() as 'user' | 'assistant',
            content: message.content
        }))
    ]

    const responseStream = new ReadableStream({
        async start(controller) {
            let messageContent = '';
            let isStreamClosed = false;

            try {
                const ollamaApiUrl = process.env.NEXT_PUBLIC_OLLAMA_URL || "http://ollama:11434";
                console.log(`Attempting to connect to Ollama at: ${ollamaApiUrl}`);
                const response = await fetch(`${ollamaApiUrl}/api/chat`, {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({
                        model: chatRoom.llmProviderModelId,
                        messages: messages,
                        stream: true,
                    }),
                });

                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }

                const reader = response.body?.getReader();
                if (!reader) throw new Error('No reader available');

                while (true) {
                    const {done, value} = await reader.read();
                    if (done) break;

                    const chunk = new TextDecoder().decode(value);
                    const lines = chunk.split('\n').filter(line => line.trim());

                    for (const line of lines) {
                        if (line.includes('[DONE]')) continue;
                        try {
                            const json = JSON.parse(line);
                            const content = json.message?.content;
                            if (content && !isStreamClosed) {
                                messageContent += content;
                                controller.enqueue(`${JSON.stringify({content: messageContent})}\n`);
                            }
                        } catch (e) {
                            console.error('Error parsing JSON:', e);
                        }
                    }
                }

                // Save to prisma after the stream is done
                if (!isStreamClosed) {
                    // First create the message
                    await prisma.chatMessage.create({
                        data: {
                            content: messageContent,
                            role: 'ASSISTANT',
                            chatRoomId: id
                        }
                    });

                    // Then handle title generation and update separately
                    if (!chatRoom.llmProviderModelId) {
                        console.error('No model ID found for chat room');
                        return null;
                    }
                    
                    const title = await generateChatTitle(messages, chatRoom.llmProvider, chatRoom.llmProviderModelId);
                    
                    // Update chat room with new title
                    await prisma.chatRoom.update({
                        where: {id}, 
                        data: {
                            lastActivityAt: new Date(),
                            name: title || messageContent.substring(0, 50) // Fallback to first 50 chars if title generation fails
                        }
                    });

                    // Send a message to trigger revalidation
                    controller.enqueue(`${JSON.stringify({type: 'title-update', title: title || messageContent.substring(0, 50)})}\n`);
                }
            } catch (error) {
                console.error('Error in chat stream:', error);
                if (!isStreamClosed) {
                    controller.enqueue(`${JSON.stringify({error: 'Failed to get response from LLM'})}\n`);
                }
            } finally {
                if (!isStreamClosed) {
                    isStreamClosed = true;
                    controller.close();
                }
            }
        }
    });

    return new NextResponse(responseStream, {
        headers: {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive'
        }
    });
}
