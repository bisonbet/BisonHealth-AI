import React from 'react';

export function NavLinks() {
    return (
        <div className="hidden items-center gap-4 mr-4 md:flex">
            <a
                href="https://github.com/bisonbet/open-health/discussions"
                target="_blank"
                rel="noopener noreferrer"
                className="text-zinc-600 dark:text-zinc-400 hover:text-zinc-900 dark:hover:text-white transition-colors font-medium"
            >
                Feedback
            </a>
            <a
                href="https://github.com/bisonbet/open-health"
                target="_blank"
                rel="noopener noreferrer"
                className="text-zinc-600 dark:text-zinc-400 hover:text-zinc-900 dark:hover:text-white transition-colors font-medium"
            >
                Github
            </a>
        </div>
    );
}
