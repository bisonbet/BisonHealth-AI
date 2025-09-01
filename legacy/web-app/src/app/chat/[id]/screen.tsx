'use client'

import React, {useEffect, useMemo, useRef, useState} from 'react';
import {Menu, Send, Settings} from 'lucide-react';
import {Button} from "@/components/ui/button";
import {Input} from "@/components/ui/input";
import LogoutButton from "@/components/auth/logout-button";
import {ThemeToggle} from "@/components/ui/theme-toggle";

import {Dialog, DialogContent, DialogHeader, DialogTitle} from "@/components/ui/dialog";
import ChatSideBar from "@/components/chat/chat-side-bar";
import ChatMessage from "@/components/chat/chat-message";
import useSWR from "swr";
import {useParams} from "next/navigation";
import {ChatMessageListResponse} from "@/app/api/chat-rooms/[id]/messages/route";
import {ChatRoomListResponse} from "@/app/api/chat-rooms/route";
import {ChatRole} from "@prisma/client";
import ChatSettingSideBar from "@/components/chat/chat-setting-side-bar";
import {useTranslations} from "next-intl";
import {NavLinks} from "@/components/ui/nav-links";

interface ScreenProps {
    isMobile: boolean;
}

export default function Screen(
    {isMobile}: ScreenProps
) {
    const {id} = useParams<{ id: string }>();
    const t = useTranslations('Chat')
    const tf = useTranslations('Feedback')

    const messagesEndRef = useRef<HTMLDivElement>(null);

    const [inputText, setInputText] = useState('');
    const [sources] = useState([]);
    const [isJsonViewerOpen, setIsJsonViewerOpen] = useState(false);
    const [isLeftSidebarOpen, setIsLeftSidebarOpen] = useState(!isMobile);
    const [isRightSidebarOpen, setIsRightSidebarOpen] = useState(!isMobile);
    const [isAssistantResponding, setIsAssistantResponding] = useState(false);

    const {data, mutate} = useSWR<ChatMessageListResponse>(`/api/chat-rooms/${id}/messages`, async (url: string) => {
        const response = await fetch(url);
        return response.json();
    });
    const messages = useMemo(() => data?.chatMessages || [], [data]);

    // Add SWR for chat rooms to handle title updates
    const {mutate: mutateChatRooms} = useSWR<ChatRoomListResponse>('/api/chat-rooms', async (url: string) => {
        const response = await fetch(url);
        return response.json();
    });

    useEffect(() => {
        if (messagesEndRef.current) {
            messagesEndRef.current.scrollIntoView({behavior: 'smooth'});
        }
    }, [messages]);

    const handleSendMessage = async () => {
        if (!inputText.trim()) return;

        // Clear input
        setInputText('');

        const userMessage = {
            id: new Date().toISOString(),
            content: inputText,
            role: 'USER' as ChatRole,
            createdAt: new Date(),
        };

        // Add user message immediately
        const oldMessages = [...messages, userMessage];
        await mutate({chatMessages: oldMessages}, {revalidate: false});

        // Set loading state and add empty assistant message
        setIsAssistantResponding(true);
        const assistantMessage = {
            id: new Date().toISOString(),
            content: '',
            role: 'ASSISTANT' as ChatRole,
            createdAt: new Date(),
        };
        await mutate({chatMessages: [...oldMessages, assistantMessage]}, {revalidate: false});

        try {
            const response = await fetch(`/api/chat-rooms/${id}/messages`, {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({
                    content: inputText,
                    role: 'USER',
                })
            });

            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }

            // Read as a stream
            const reader = response.body?.getReader();
            const decoder = new TextDecoder();

            if (reader) {
                try {
                    while (true) {
                        const {value, done} = await reader.read();
                        if (done) break;

                        const chunk = decoder.decode(value, {stream: true});
                        const lines = chunk.split('\n').filter(Boolean);

                        for (const line of lines) {
                            try {
                                const data = JSON.parse(line);
                                if (data.error) {
                                    console.error('Error from LLM:', data.error);
                                    continue;
                                }
                                if (data.content) {
                                    assistantMessage.content = data.content;
                                    await mutate({
                                        chatMessages: [...oldMessages, assistantMessage]
                                    }, {revalidate: false});
                                }
                                if (data.type === 'title-update') {
                                    // Trigger a revalidation of the chat rooms list to update the title
                                    await mutateChatRooms();
                                }
                            } catch (e) {
                                console.error('Error parsing stream chunk:', e);
                            }
                        }
                    }
                } catch (e) {
                    console.error('Error reading stream:', e);
                    throw e;
                } finally {
                    reader.releaseLock();
                }
            }

            // Final revalidation to ensure we have the latest state
            await mutate();
        } catch (error) {
            console.error('Error in chat:', error);
            // Add error message to chat
            const errorMessage = {
                id: new Date().toISOString(),
                content: 'Sorry, there was an error processing your message. Please try again.',
                role: 'ASSISTANT' as ChatRole,
                createdAt: new Date(),
            };
            await mutate({
                chatMessages: [...oldMessages, errorMessage]
            }, {revalidate: false});
        } finally {
            setIsAssistantResponding(false);
        }
    };

    return (
        <div className="h-screen flex flex-col">
            <div className="bg-background border-b h-14 flex items-center px-4 shrink-0">
                <div className="flex items-center gap-2">
                    <Button variant="ghost" size="default" onClick={() => setIsLeftSidebarOpen(!isLeftSidebarOpen)}>
                        <Menu className="w-4 h-4"/>
                    </Button>
                    <h1 className="text-lg font-semibold">OpenHealth</h1>
                </div>
                <div className="flex-1"/>
                <div className="flex items-center gap-4">
                    <NavLinks/>
                    <div className="flex items-center gap-1">
                        <ThemeToggle />
                        <LogoutButton/>
                        <Button variant="ghost" size="default"
                                onClick={() => setIsRightSidebarOpen(!isRightSidebarOpen)}>
                            <Settings className="w-4 h-4"/>
                        </Button>
                    </div>
                </div>
            </div>

            <div className="flex-1 flex overflow-hidden">
                {/* Left sidebar */}
                {isLeftSidebarOpen && (
                    <div className="w-72 border-r bg-background flex flex-col overflow-hidden">
                        <ChatSideBar chatRoomId={id} isLeftSidebarOpen={true}/>
                    </div>
                )}

                {/* Main content */}
                <div className="flex-1 flex flex-col bg-background min-w-0">
                    <div className="flex-1 overflow-y-auto p-2 space-y-2">
                        {messages.map((message, index) => (
                            <ChatMessage 
                                key={message.id} 
                                message={message}
                                isLoading={isAssistantResponding && index === messages.length - 1 && message.role === 'ASSISTANT' && !message.content}
                            />
                        ))}
                        <div ref={messagesEndRef}/>
                    </div>
                    <div className="mb-16 md:mb-0">
                        <div className="p-4 flex items-center justify-between">
                            <div className="text-sm text-blue-800 flex-1 pr-4"/>
                            <div className="flex gap-2 items-center shrink-0">
                                <Button
                                    variant="outline"
                                    size="sm"
                                    className="text-zinc-600 dark:text-zinc-400 border-zinc-200 dark:border-zinc-700 hover:bg-zinc-100 dark:hover:bg-zinc-800"
                                    onClick={() => window.open('https://www.zocdoc.com/', '_blank')}
                                >
                                    {tf('findADoctor')}
                                </Button>
                                <Button
                                    variant="outline"
                                    size="sm"
                                    className="text-zinc-600 dark:text-zinc-400 border-zinc-200 dark:border-zinc-700 hover:bg-zinc-100 dark:hover:bg-zinc-800"
                                    onClick={() => window.open(`https://www.reddit.com/r/AskDocs`, '_blank')}
                                >
                                    {tf('askADoctor')}
                                </Button>
                            </div>
                        </div>
                        <div className="border-t p-4 z-10 md:static fixed bottom-0 left-0 w-full bg-background">
                            <div className="flex gap-2">
                                <Input
                                    placeholder={t('inputPlaceholder')}
                                    value={inputText}
                                    onChange={(e) => setInputText(e.target.value)}
                                    onKeyPress={(e) => {
                                        if (e.key === 'Enter' && !e.shiftKey) {
                                            e.preventDefault();
                                            handleSendMessage();
                                        }
                                    }}
                                />
                                <Button onClick={handleSendMessage}>
                                    <Send className="w-4 h-4"/>
                                </Button>
                            </div>
                        </div>
                    </div>
                </div>

                {/* Right sidebar */}
                {isRightSidebarOpen && (
                    <div className="w-80 border-l bg-background flex flex-col overflow-y-auto">
                        <ChatSettingSideBar chatRoomId={id}/>
                    </div>
                )}
            </div>

            <Dialog open={isJsonViewerOpen} onOpenChange={setIsJsonViewerOpen}>
                <DialogContent className="max-w-2xl max-h-[80vh]">
                    <DialogHeader><DialogTitle>Source Data</DialogTitle></DialogHeader>
                    <div className="overflow-y-auto">
            <pre className="text-xs bg-gray-50 p-4 rounded overflow-auto">
              {JSON.stringify(sources, null, 2)}
            </pre>
                    </div>
                </DialogContent>
            </Dialog>
        </div>
    );
}
