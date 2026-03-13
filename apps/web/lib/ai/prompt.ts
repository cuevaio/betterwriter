import { streamText } from "ai";
import {
  WRITING_PROMPT_SYSTEM,
  DAY_1_WRITING_PROMPT_SYSTEM,
  DAY_0_WRITE_PROMPT,
  DAY_1_PROMPT_TEMPLATE,
} from "./constants";
import { aiModel, retrieveMemoryContext, withMemorySystem } from "./mem0";
import { streamConstant } from "./stream-utils";

/**
 * Extract the plain title from the first **bold** line of the reading body markdown.
 */
function extractTitleFromBody(body: string): string {
  const firstLine = body.split("\n")[0]?.trim() ?? "";
  return firstLine.replace(/^\*\*|\*\*$/g, "").trim() || "the reading";
}

/**
 * Generate a writing prompt for a given day.
 */
export async function generateWritingPrompt(options: {
  userId: string;
  dayIndex: number;
  aboutDayIndex: number;
  readingBody: string | null;
  day0WritingText: string;
}): Promise<string> {
  return streamWritingPromptCore(options, async () => {});
}

async function streamWritingPromptCore(
  options: Parameters<typeof generateWritingPrompt>[0],
  onDelta: (delta: string) => void | Promise<void>,
): Promise<string> {
  const {
    userId,
    dayIndex,
    aboutDayIndex,
    readingBody,
    day0WritingText,
  } = options;

  // Day 0: fixed prompt — stream in chunks for smooth animation
  if (dayIndex === 0) {
    await streamConstant(DAY_0_WRITE_PROMPT, onDelta);
    return DAY_0_WRITE_PROMPT;
  }

  let promptText: string;
  let systemPrompt = WRITING_PROMPT_SYSTEM;
  if (dayIndex === 1) {
    const day0Intro = day0WritingText.trim();
    const introForPrompt =
      day0Intro.length > 0
        ? day0Intro
        : "The user did not provide a day-0 introduction. Ask them to share one meaningful detail about who they are and what they want to explore through writing.";
    promptText = DAY_1_PROMPT_TEMPLATE.replace("{userIntro}", introForPrompt);
    systemPrompt = DAY_1_WRITING_PROMPT_SYSTEM;
  } else if (!readingBody) {
    promptText = "Write about whatever is on your mind today. What have you been thinking about recently?";
  } else {
    const readingTitle = extractTitleFromBody(readingBody);
    promptText = `The user read a passage titled "${readingTitle}". Here's the passage:

${readingBody}

This prompt is for day ${dayIndex}, writing about day ${aboutDayIndex}.

Generate a writing prompt that connects a specific idea from this reading to the user's life or perspective. Make them want to write.`;
  }

  const result = streamText({
    model: aiModel(userId),
    system: withMemorySystem(
      systemPrompt,
      await retrieveMemoryContext(userId, promptText)
    ),
    prompt: promptText,
    maxOutputTokens: 400,
  });

  let accumulated = "";
  for await (const delta of result.textStream) {
    if (!delta) continue;
    accumulated += delta;
    await onDelta(delta);
  }

  const normalized = accumulated.trim();
  if (normalized) {
    return normalized;
  }

  const fallback = "Write about whatever is on your mind today. What have you been thinking about recently?";
  await streamConstant(fallback, onDelta);
  return fallback;
}

export async function streamWritingPrompt(
  options: Parameters<typeof generateWritingPrompt>[0],
  onDelta: (delta: string) => void | Promise<void>,
): Promise<string> {
  return streamWritingPromptCore(options, onDelta);
}
