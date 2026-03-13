import { streamText } from "ai";
import { searchExa } from "@/lib/exa";
import { aiModel, retrieveMemoryContext, withMemorySystem } from "./mem0";
import {
  READING_CURATION_PROMPT,
  READING_FALLBACK_PROMPT,
  DAY_0_WELCOME_TEXT,
} from "./constants";
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
  dayIndex: number,
): Promise<GeneratedReading> {
  return generateReadingStream(userId, dayIndex, async () => {});
}

async function pickExaSource(
  topic: string,
): Promise<ExaPickedSource> {
  const query = `${topic} essay interesting perspective thought-provoking`;
  const results = await searchExa(query, { numResults: 5 });

  const usable = results.filter((r) => r.text && r.text.length >= 500);
  if (usable.length === 0) {
    throw new Error("No usable Exa results");
  }

  return {
    title: usable[0].title,
    text: usable[0].text ?? "",
    url: usable[0].url,
  };
}

export async function generateReadingStream(
  userId: string,
  dayIndex: number,
  onDelta: (delta: string) => void | Promise<void>,
): Promise<GeneratedReading> {
  if (dayIndex === 0) {
    await streamConstant(DAY_0_WELCOME_TEXT.body, onDelta);
    return { body: DAY_0_WELCOME_TEXT.body };
  }

  // Use memory context to determine a good topic
  const memoryContext = await retrieveMemoryContext(
    userId,
    "What topics and interests does this user care about? What would they want to read?"
  );
  const topic = memoryContext.trim() || "interesting ideas and perspectives";

  let sourceURL: string | null = null;
  let sourceTitle: string | null = null;
  let sourceText: string | null = null;

  try {
    const picked = await pickExaSource(topic);
    sourceURL = picked.url;
    sourceTitle = picked.title;
    sourceText = picked.text;
  } catch (error) {
    console.error("Reading stream: Exa source lookup failed, using original generation", error);
  }

  const streamPrompt = sourceText
    ? `Topic: ${topic}
Source title: ${sourceTitle}
Source text:
${sourceText}

Write a curated passage. Start with a bold title line (**Title**), then a blank line, then the body (400-600 words).`
    : `Write an original, thought-provoking passage about: ${topic}

Start with a bold title line (**Title**), then a blank line, then the body (400-600 words).`;

  const bodyResult = streamText({
    model: aiModel(userId),
    system: withMemorySystem(
      sourceText ? READING_CURATION_PROMPT : READING_FALLBACK_PROMPT,
      memoryContext
    ),
    prompt: streamPrompt,
    maxOutputTokens: 1200,
  });

  let body = "";
  for await (const delta of bodyResult.textStream) {
    if (!delta) continue;
    body += delta;
    await onDelta(delta);
  }

  const normalizedBody = body.trim();
  if (!normalizedBody) {
    throw new Error("No output generated.");
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
