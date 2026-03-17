import { streamText } from "ai";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { entries } from "@/lib/db/schema";
import { searchExa } from "@/lib/exa";
import {
  DAY_0_WELCOME_TEXT,
  readingCurationPrompt,
  readingFallbackPrompt,
} from "./constants";
import { aiModel, retrieveMemoryContext, withMemorySystem } from "./mem0";
import { streamConstant } from "./stream-utils";

interface GeneratedReading {
  body: string;
}

interface ExaPickedSource {
  title: string;
  text: string;
  url: string;
}

/**
 * Generate a reading for a given user and day index.
 */
export async function generateReading(
  userId: string,
  dayIndex: number
): Promise<GeneratedReading> {
  return generateReadingStream(userId, dayIndex, async () => {});
}

/**
 * Extract source URLs from past reading bodies.
 * Readings end with `[Read the full article on host](url)`.
 */
function extractUrlsFromReadings(bodies: string[]): Set<string> {
  const urlPattern = /\[Read the full article on [^\]]+\]\(([^)]+)\)/g;
  const urls = new Set<string>();
  for (const body of bodies) {
    for (const match of body.matchAll(urlPattern)) {
      urls.add(match[1]);
    }
  }
  return urls;
}

/**
 * Fetch URLs from this user's past readings to avoid repeating sources.
 */
async function getPastReadingUrls(userId: string): Promise<Set<string>> {
  const rows = await db
    .select({ readingBody: entries.readingBody })
    .from(entries)
    .where(eq(entries.userId, userId));

  const bodies = rows
    .map((r) => r.readingBody)
    .filter((b): b is string => b !== null);

  return extractUrlsFromReadings(bodies);
}

const QUERY_SUFFIXES = [
  "essay interesting perspective thought-provoking",
  "deep dive analysis opinion",
  "insights lessons learned reflection",
  "story narrative personal experience",
  "research findings surprising facts",
];

async function pickExaSource(
  topic: string,
  excludeUrls: Set<string>
): Promise<ExaPickedSource> {
  const maxRetries = QUERY_SUFFIXES.length;

  console.log(
    `[pickExaSource] topic="${topic}", excludeUrls=${excludeUrls.size}`
  );

  for (let attempt = 0; attempt < maxRetries; attempt++) {
    const suffix = QUERY_SUFFIXES[attempt];
    const query = `${topic} ${suffix}`;
    const numResults = 5 + attempt * 5; // 5, 10, 15, 20, 25

    console.log(
      `[pickExaSource] attempt ${attempt + 1}/${maxRetries}: query="${query}", numResults=${numResults}`
    );

    const results = await searchExa(query, { numResults });

    const tooShort = results.filter(
      (r) => !r.text || r.text.length < 500
    ).length;
    const excluded = results.filter(
      (r) => r.text && r.text.length >= 500 && excludeUrls.has(r.url)
    ).length;
    const usable = results.filter(
      (r) => r.text && r.text.length >= 500 && !excludeUrls.has(r.url)
    );

    console.log(
      `[pickExaSource] attempt ${attempt + 1}/${maxRetries}: ${results.length} raw results, ${tooShort} too short, ${excluded} excluded (already read), ${usable.length} usable`
    );

    if (usable.length > 0) {
      const pick = usable[Math.floor(Math.random() * usable.length)];
      console.log(
        `[pickExaSource] picked: "${pick.title}" (${pick.text?.length ?? 0} chars) ${pick.url}`
      );
      return {
        title: pick.title,
        text: pick.text ?? "",
        url: pick.url,
      };
    }

    // Log which URLs were excluded for debugging
    if (excluded > 0) {
      const excludedUrls = results
        .filter((r) => r.text && r.text.length >= 500 && excludeUrls.has(r.url))
        .map((r) => r.url);
      console.log(`[pickExaSource] excluded URLs: ${excludedUrls.join(", ")}`);
    }
  }

  console.error(
    `[pickExaSource] FAILED after ${maxRetries} attempts for topic: "${topic}"`
  );
  throw new Error(
    `No usable Exa results after ${maxRetries} attempts for topic: ${topic}`
  );
}

/**
 * Returns the word count range for a given day index.
 * Word count increases by 100 every 7 completed app days (one "week").
 * Week 1 (days 0–6): 200–300 words
 * Week 2 (days 7–13): 300–400 words
 * Week N: (100N+100)–(100N+200) words
 */
function getWordCountRange(dayIndex: number): { min: number; max: number } {
  const weekNumber = Math.floor(dayIndex / 7) + 1;
  return {
    min: 200 + (weekNumber - 1) * 100,
    max: 300 + (weekNumber - 1) * 100,
  };
}

export async function generateReadingStream(
  userId: string,
  dayIndex: number,
  onDelta: (delta: string) => void | Promise<void>,
  weekDayIndex?: number
): Promise<GeneratedReading> {
  if (dayIndex === 0) {
    await streamConstant(DAY_0_WELCOME_TEXT.body, onDelta);
    return { body: DAY_0_WELCOME_TEXT.body };
  }

  const { min, max } = getWordCountRange(weekDayIndex ?? dayIndex);

  // Use memory context to determine a good topic
  console.log(`[generateReadingStream] userId=${userId}, dayIndex=${dayIndex}`);
  const memoryContext = await retrieveMemoryContext(
    userId,
    "What topics and interests does this user care about? What would they want to read?"
  );
  const topic = memoryContext.trim() || "interesting ideas and perspectives";
  console.log(
    `[generateReadingStream] topic="${topic.slice(0, 200)}${topic.length > 200 ? "..." : ""}"`
  );

  let sourceURL: string | null = null;
  let sourceTitle: string | null = null;
  let sourceText: string | null = null;

  try {
    const pastUrls = await getPastReadingUrls(userId);
    console.log(
      `[generateReadingStream] ${pastUrls.size} past reading URLs to exclude`
    );
    const picked = await pickExaSource(topic, pastUrls);
    sourceURL = picked.url;
    sourceTitle = picked.title;
    sourceText = picked.text;
    console.log(
      `[generateReadingStream] Exa source: "${sourceTitle}" (${sourceText?.length ?? 0} chars)`
    );
  } catch (error) {
    console.error(
      "[generateReadingStream] Exa source lookup failed, using AI-only generation:",
      error instanceof Error ? error.message : error
    );
  }

  console.log(
    `[generateReadingStream] mode=${sourceText ? "curated" : "original"}, wordRange=${min}-${max}`
  );

  const streamPrompt = sourceText
    ? `Topic: ${topic}
Source title: ${sourceTitle}
Source text:
${sourceText}

Write a curated passage. Start with a bold title line (**Title**), then a blank line, then the body (${min}-${max} words).`
    : `Write an original, thought-provoking passage about: ${topic}

Start with a bold title line (**Title**), then a blank line, then the body (${min}-${max} words).`;

  const bodyResult = streamText({
    model: aiModel(userId),
    system: withMemorySystem(
      sourceText
        ? readingCurationPrompt(min, max)
        : readingFallbackPrompt(min, max),
      memoryContext
    ),
    prompt: streamPrompt,
    // Use a generous limit to accommodate reasoning models (e.g. gpt-oss-120b)
    // that spend tokens on chain-of-thought before producing the visible text.
    maxOutputTokens: Math.max(8192, max * 8),
  });

  let body = "";
  for await (const delta of bodyResult.textStream) {
    if (!delta) continue;
    body += delta;
    await onDelta(delta);
  }

  const normalizedBody = body.trim();
  if (!normalizedBody) {
    // Capture diagnostics to understand why the model returned no text.
    const [finishReason, usage, warnings, reasoningText] = await Promise.all([
      bodyResult.finishReason,
      bodyResult.usage,
      bodyResult.warnings,
      bodyResult.reasoningText,
    ]);
    console.error("Reading stream: empty output", {
      dayIndex,
      finishReason,
      usage,
      warnings,
      hadExaSource: !!sourceText,
      model: aiModel(userId),
      reasoningLength: reasoningText?.length ?? 0,
    });
    throw new Error(
      `No output generated (finishReason: ${finishReason}, inputTokens: ${usage?.inputTokens ?? "?"}, outputTokens: ${usage?.outputTokens ?? "?"}).`
    );
  }

  // Append source link as the final line
  if (sourceURL) {
    try {
      const host = new URL(sourceURL).hostname;
      const linkMarkdown = `\n\n[Read the full article on ${host}](${sourceURL})`;
      await onDelta(linkMarkdown);
      return { body: normalizedBody + linkMarkdown };
    } catch {
      // malformed URL — just return body without link
    }
  }

  return { body: normalizedBody };
}
