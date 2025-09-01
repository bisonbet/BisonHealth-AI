import {getRequestConfig} from 'next-intl/server';

export default getRequestConfig(async () => {
    // Simplified to always use English to avoid dynamic import issues
    const locale = 'en';
    const messages = (await import(`../../messages/en.json`)).default;
    
    return {locale, messages};
})