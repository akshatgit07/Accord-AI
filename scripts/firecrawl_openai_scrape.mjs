import dotenv from 'dotenv';
import { Firecrawl } from 'firecrawl';
import OpenAI from 'openai';

dotenv.config({ path: '.env' });
dotenv.config({ path: '.env.local' });

const url = process.argv[2];

if (!url) {
  console.error('Usage: npm run scrape:summary -- https://example.com');
  process.exit(1);
}

if (!process.env.FIRECRAWL_API_KEY) {
  console.error('Missing FIRECRAWL_API_KEY. Add it to .env.local or your shell environment.');
  process.exit(1);
}

if (!process.env.OPENAI_API_KEY) {
  console.error('Missing OPENAI_API_KEY. Add it to .env.local or your shell environment.');
  process.exit(1);
}

const firecrawl = new Firecrawl({ apiKey: process.env.FIRECRAWL_API_KEY });
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

const scrapeResult = await firecrawl.scrape(url, {
  formats: ['markdown'],
  onlyMainContent: true,
});

const markdown = scrapeResult.markdown ?? scrapeResult.data?.markdown ?? '';
console.log('Scraped content length:', markdown.length);

const completion = await openai.chat.completions.create({
  model: process.env.OPENAI_SUMMARY_MODEL ?? 'gpt-5-nano',
  messages: [
    {
      role: 'user',
      content: `Summarize this scraped page for geopolitical/event intelligence extraction. Keep concrete actors, locations, claims, dates, and source context.\n\nURL: ${url}\n\n${markdown.slice(0, 20000)}`,
    },
  ],
});

console.log('Summary:', completion.choices[0]?.message.content ?? '');
