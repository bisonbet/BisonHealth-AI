'use client';

import {Select, SelectContent, SelectItem, SelectTrigger, SelectValue} from "@/components/ui/select";
import {Textarea} from "@/components/ui/textarea";
import React, {useCallback, useEffect, useMemo, useState} from "react";
import useSWR from "swr";
import {AssistantMode, AssistantModeListResponse} from "@/app/api/assistant-modes/route";
import {ChatRoomGetResponse} from "@/app/api/chat-rooms/[id]/route";
import {AssistantModePatchRequest} from "@/app/api/assistant-modes/[id]/route";
import {LLMProvider, LLMProviderListResponse} from "@/app/api/llm-providers/route";
import {LLMProviderModel, LLMProviderModelListResponse} from "@/app/api/llm-providers/[id]/models/route";
import {useTranslations} from "next-intl";
import Link from "next/link";
import {Plus} from "lucide-react";
import {CHAT_MODEL_PREFERENCES, getFirstAvailableModel} from "@/config/model-preferences";

interface ChatSettingSideBarProps {
    chatRoomId: string;
}

export default function ChatSettingSideBar({chatRoomId}: ChatSettingSideBarProps
) {
    const t = useTranslations('ChatSettingSideBar')

    const [selectedAssistantMode, setSelectedAssistantMode] = useState<AssistantMode>();
    const [selectedLLMProvider, setSelectedLLMProvider] = useState<LLMProvider>();
    const [selectedLLMProviderModel, setSelectedLLMProviderModel] = useState<LLMProviderModel>();
    const [llmProviderModels, setLLMProviderModels] = useState<LLMProviderModel[]>([]);

    const {
        data: chatRoomData,
        mutate: chatRoomMutate
    } = useSWR<ChatRoomGetResponse>(`/api/chat-rooms/${chatRoomId}`, async (url: string) => {
        const response = await fetch(url);
        return response.json();
    });

    const {
        data: llmProvidersData,
    } = useSWR<LLMProviderListResponse>('/api/llm-providers', async (url: string) => {
        const response = await fetch(url);
        return response.json();
    })

    const onChangeChatRoom = useCallback(async ({
        assistantModeId,
        llmProviderId,
        llmProviderModelId,
    }: {
        assistantModeId?: string
        llmProviderId?: string
        llmProviderModelId?: string | null
    }) => {
        if (chatRoomData === undefined) return;
        const response = await fetch(`/api/chat-rooms/${chatRoomId}`, {
            method: 'PATCH',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({assistantModeId, llmProviderId, llmProviderModelId}),
        });
        const data = await response.json();

        // Get the saved system prompt
        const updatedAssistantMode = {
            ...data.chatRoom.assistantMode,
            systemPrompt: data.chatRoom.assistantMode.systemPrompt
        };

        await chatRoomMutate({
            ...chatRoomData,
            chatRoom: {
                ...chatRoomData.chatRoom,
                assistantMode: updatedAssistantMode,
                llmProviderId: llmProviderId || chatRoomData.chatRoom.llmProviderId,
                llmProviderModelId: llmProviderModelId || chatRoomData.chatRoom.llmProviderModelId,
            }
        });
        setSelectedAssistantMode(updatedAssistantMode);
    }, [chatRoomData, chatRoomId, chatRoomMutate]);

    useEffect(() => {
        onChangeChatRoom({
            llmProviderModelId: selectedLLMProviderModel?.id
        })
    }, [selectedLLMProviderModel, onChangeChatRoom]);

    // Initialize assistant mode from localStorage or chatRoomData
    useEffect(() => {
        if (!chatRoomData?.chatRoom.assistantMode) return;

        // If no saved prompt, use the current one and save it
        setSelectedAssistantMode(chatRoomData.chatRoom.assistantMode);
    }, [chatRoomData?.chatRoom.assistantMode]);

    useEffect(() => {
        const chatRoom = chatRoomData?.chatRoom;
        if (!chatRoom) return;

        const llmProviders = llmProvidersData?.llmProviders || [];
        const models = llmProviderModels || [];

        if (selectedLLMProvider === undefined && llmProviders.length > 0) {
            setSelectedLLMProvider(llmProviders.find((provider) => provider.id === chatRoom.llmProviderId) || llmProviders[0]);
        }

        if (selectedLLMProviderModel === undefined && models.length > 0) {
            // Try to find the model from preferences first
            const initializeModel = async () => {
                const preferredModel = await getFirstAvailableModel(CHAT_MODEL_PREFERENCES);
                if (preferredModel) {
                    const model = models.find((m) => m.id === preferredModel.id);
                    if (model) {
                        setSelectedLLMProviderModel(model);
                        return;
                    }
                }
                // Fallback to saved model or first available
                setSelectedLLMProviderModel(models.find((model) => model.id === chatRoom.llmProviderModelId) || models[0]);
            };
            initializeModel();
        }
    }, [chatRoomData, llmProvidersData, llmProviderModels, selectedLLMProvider, selectedLLMProviderModel]);

    const {
        data: assistantModesData,
        mutate: assistantModesMutate
    } = useSWR<AssistantModeListResponse>('/api/assistant-modes', async (url: string) => {
        const response = await fetch(url);
        return response.json();
    })
    const assistantModes = useMemo(() => assistantModesData?.assistantModes || [], [assistantModesData]);

    // Fetch models when LLM is selected
    useEffect(() => {
        if (!selectedLLMProvider) return;
        const fetchLLMProviderModels = async () => {
            const response = await fetch(`/api/llm-providers/${selectedLLMProvider.id}/models`)
            const data: LLMProviderModelListResponse = await response.json();
            setLLMProviderModels(data.llmProviderModels || []);
        }
        fetchLLMProviderModels();
    }, [selectedLLMProvider]);

    const onChangeAssistantMode = async (assistantModeId: string, body: AssistantModePatchRequest) => {
        const response = await fetch(`/api/assistant-modes/${assistantModeId}`, {
            method: 'PATCH',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify(body),
        })
        const data = await response.json();

        await assistantModesMutate({
            ...assistantModesData,
            assistantModes: assistantModesData?.assistantModes.map((assistantMode) => {
                if (assistantMode.id === assistantModeId) {
                    return data.assistantMode;
                }
                return assistantMode;
            }) || []
        })
    }

    return <div className="h-full overflow-y-auto">
        <div className="p-4 space-y-4">
            <div className="space-y-4">
                <h4 className="text-sm font-medium">{t('modelSettings')}</h4>
                <div className="space-y-2">
                    <Select value={selectedLLMProvider?.id}
                            onValueChange={(value) => {
                                setSelectedLLMProvider(llmProvidersData?.llmProviders.find((provider) => provider.id === value));
                                setLLMProviderModels([])
                                setSelectedLLMProviderModel(undefined);
                                onChangeChatRoom({llmProviderId: value, llmProviderModelId: null});
                            }}>
                        <SelectTrigger>
                            <SelectValue placeholder={t('selectCompany')}/>
                        </SelectTrigger>
                        <SelectContent className="bg-background border border-border">
                            {llmProvidersData?.llmProviders.map((provider) => <SelectItem
                                key={provider.id}
                                value={provider.id}>{provider.name}</SelectItem>)}
                        </SelectContent>
                    </Select>
                    <Select value={selectedLLMProviderModel?.id}
                            onValueChange={(value) => setSelectedLLMProviderModel(llmProviderModels.find((model) => model.id === value))}>
                        <SelectTrigger>
                            <SelectValue placeholder={t('selectModel')}/>
                        </SelectTrigger>
                        <SelectContent className="bg-background border border-border">
                            {llmProviderModels.map((model) => (
                                <SelectItem key={model.id} value={model.id}>
                                    {model.name}
                                </SelectItem>
                            ))}

                            {llmProviderModels.length === 0 && (
                                <div className="p-2 text-sm text-muted-foreground">{t('noModelsFound')}</div>
                            )}
                        </SelectContent>
                    </Select>

                    <div className="text-sm text-muted-foreground">
                        Using Ollama API endpoint: {process.env.NEXT_PUBLIC_OLLAMA_URL || 'http://ollama:11434'}
                    </div>
                </div>
            </div>

            <div className="space-y-2">
                <label className="text-sm font-medium">{t('systemPrompt')}</label>
                <Textarea
                    value={selectedAssistantMode?.systemPrompt || ''}
                    onChange={async (e) => {
                        if (selectedAssistantMode) {
                            setSelectedAssistantMode({...selectedAssistantMode, systemPrompt: e.target.value});
                            await onChangeAssistantMode(selectedAssistantMode.id, {systemPrompt: e.target.value});
                        }
                    }}
                    rows={6}
                    className="resize-none"
                />
            </div>

            <div className="space-y-3">
                <div className="flex items-center justify-between">
                    <h4 className="text-sm font-medium">{t('assistantMode')}</h4>
                    <Link href="/assistant-modes/add"
                          className="inline-flex items-center text-xs text-primary hover:text-primary/80">
                        <Plus className="mr-1 h-3 w-3"/>
                        {t('addAssistant')}
                    </Link>
                </div>
                <div className="space-y-2">
                    {assistantModes.map((assistantMode) => (
                        <button
                            key={assistantMode.id}
                            className={`w-full p-3 rounded-lg text-left border transition-colors
                        ${selectedAssistantMode?.id === assistantMode.id ? 'bg-accent border-border' :
                                'border-transparent hover:bg-accent'}`}
                            onClick={async () => {
                                await onChangeChatRoom({assistantModeId: assistantMode.id});
                            }}
                        >
                            <div className="text-sm font-medium">{assistantMode.name}</div>
                            <div className="text-xs text-muted-foreground">{assistantMode.description}</div>
                        </button>
                    ))}
                </div>
            </div>
        </div>
    </div>
}
