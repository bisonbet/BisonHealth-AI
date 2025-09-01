import React from 'react';
import { Github } from 'lucide-react';

export function Footer() {
  return (
    <footer className="fixed bottom-0 w-full h-12 bg-white/80 dark:bg-zinc-900/80 backdrop-blur-md border-t border-zinc-200 dark:border-zinc-800">
      <div className="h-full container mx-auto flex justify-center items-center gap-6">
        <a
          href="https://github.com/bisonbet/open-health"
          target="_blank"
          rel="noopener noreferrer"
          className="flex items-center gap-1.5 px-2 text-zinc-500 dark:text-zinc-400 hover:text-zinc-900 dark:hover:text-white transition-all"
        >
          <Github className="w-[14px] h-[14px]" />
          <span className="text-[13px] font-medium">Github</span>
        </a>
      </div>
    </footer>
  );
} 
