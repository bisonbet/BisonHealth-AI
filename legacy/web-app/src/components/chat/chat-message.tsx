import React, {useState} from "react";
import type {ChatMessage as ChatMessageType} from "@/app/api/chat-rooms/[id]/messages/route";
import Markdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import remarkMath from 'remark-math'
import rehypeKatex from 'rehype-katex'
import Image from 'next/image'
import {cn} from "@/lib/utils";
import {Button} from "@/components/ui/button";
import {ChevronDown, ChevronRight} from "lucide-react";

interface ChatMessageProps {
    message: ChatMessageType;
    isLoading?: boolean;
}

interface ThinkingContent {
    content: string;
    startIndex: number;
    endIndex: number;
}

function extractThinkingContent(text: string): { thinkingContent: ThinkingContent[], displayContent: string } {
    const thinkingContent: ThinkingContent[] = [];
    let displayContent = text;
    let offset = 0;

    const thinkRegex = /<think>([\s\S]*?)<\/think>/g;
    let match;

    while ((match = thinkRegex.exec(text)) !== null) {
        const fullMatch = match[0];
        const content = match[1];
        const startIndex = match.index - offset;
        const endIndex = startIndex + fullMatch.length;

        thinkingContent.push({
            content,
            startIndex,
            endIndex
        });

        // Replace the think tag with a placeholder
        displayContent = displayContent.replace(fullMatch, '');
        offset += fullMatch.length;
    }

    return { thinkingContent, displayContent };
}

export default function ChatMessage(
    {message, isLoading = false}: ChatMessageProps
) {
    const [expandedThinking, setExpandedThinking] = useState<number[]>([]);
    const { thinkingContent, displayContent } = extractThinkingContent(message.content);

    const toggleThinking = (index: number) => {
        setExpandedThinking(prev => 
            prev.includes(index) 
                ? prev.filter(i => i !== index)
                : [...prev, index]
        );
    };

    return <div className={`flex gap-2 ${message.role === 'ASSISTANT' ? 'bg-muted dark:bg-muted/50' : ''} p-2 rounded`}>
        {message.role === 'ASSISTANT' && (
            <div className="shrink-0 mt-1">
                <Image
                    src="/favicon.ico"
                    alt="Assistant"
                    width={24}
                    height={24}
                    className="rounded-full"
                />
            </div>
        )}
        <div className={`flex-1 ${message.role === 'USER' ? 'text-right' : ''}`}>
            {isLoading ? (
                <div className="flex items-center space-x-2 py-2">
                    <div className="w-3 h-3 bg-primary rounded-full animate-pulse" />
                    <div className="w-3 h-3 bg-primary rounded-full animate-pulse delay-150" />
                    <div className="w-3 h-3 bg-primary rounded-full animate-pulse delay-300" />
                </div>
            ) : (
                <Markdown className={cn(
                    'text-sm',
                    message.role === 'USER' ? undefined : 'prose dark:prose-invert'
                )}
                          remarkPlugins={[remarkGfm, remarkMath]}
                          rehypePlugins={[rehypeKatex]}
                >
                    {displayContent}
                </Markdown>
            )}
            
            {message.role === 'ASSISTANT' && thinkingContent.length > 0 && (
                <div className="mt-2 space-y-2">
                    {thinkingContent.map((thinking, index) => (
                        <div key={index} className="border rounded-md overflow-hidden">
                            <Button
                                variant="ghost"
                                className="w-full justify-start px-3 py-1 h-auto text-xs text-muted-foreground hover:text-foreground"
                                onClick={() => toggleThinking(index)}
                            >
                                {expandedThinking.includes(index) ? (
                                    <ChevronDown className="w-4 h-4 mr-1" />
                                ) : (
                                    <ChevronRight className="w-4 h-4 mr-1" />
                                )}
                                Thinking Process
                            </Button>
                            {expandedThinking.includes(index) && (
                                <div className="px-3 py-2 bg-muted/50 text-sm">
                                    <Markdown
                                        remarkPlugins={[remarkGfm, remarkMath]}
                                        rehypePlugins={[rehypeKatex]}
                                    >
                                        {thinking.content}
                                    </Markdown>
                                </div>
                            )}
                        </div>
                    ))}
                </div>
            )}
        </div>
    </div>
}
