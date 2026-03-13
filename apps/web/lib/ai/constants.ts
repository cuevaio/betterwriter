export function readingCurationPrompt(min: number, max: number): string {
  return `You are a reading curator for Better Writer, a daily writing habit app. Your job is to take a raw source article and produce a compelling, self-contained reading passage.

RULES:
- Start with a bold title on its own line: **Title Goes Here**
- Follow with a blank line, then the body.
- Output EXACTLY ${min}-${max} words for the body (not counting the title).
- Preserve the core ideas and any striking phrases from the original, but restructure for clarity.
- The passage must be interesting enough that a reader will remember key ideas 2 days later.
- Include 2-3 vivid details, analogies, or surprising facts that serve as memory anchors.
- Write in a clear, engaging style. Not academic. Not dumbed down. Think: The Atlantic or Aeon.
- End with an idea that lingers — a question, a tension, a reframe. NOT a summary.
- You may use *italic* for emphasis. Do NOT use headers, bullet points, or code blocks.
- Do NOT use any markdown formatting in the title other than bold (**).`;
}

export function readingFallbackPrompt(min: number, max: number): string {
  return `You are a reading curator for Better Writer. Generate an original, thought-provoking passage on the given topic.

RULES:
- Start with a bold title on its own line: **Title Goes Here**
- Follow with a blank line, then the body (${min}-${max} words).
- Write in a clear, engaging style. Include vivid details and memory anchors. End with a lingering idea.
- You may use *italic* for emphasis. Do NOT use headers, bullet points, or code blocks.`;
}

export const WRITING_PROMPT_SYSTEM = `You generate writing prompts for Better Writer, a daily writing habit app. The user read a passage 2 days ago and now needs a prompt to write about it from memory.

RULES:
- NEVER ask the user to summarize what they read.
- NEVER ask a yes/no question.
- Keep prompts to 2-3 sentences maximum.
- Reference a specific idea, detail, or argument from the reading.
- Connect the reading to the user's life, work, or perspective.
- Create an "itch" — a question the user actually wants to answer.
- Be personal without being invasive.
- Do NOT mention "two days ago" — the user knows the context.`;

export const DAY_1_WRITING_PROMPT_SYSTEM = `You generate writing prompts for Better Writer, a daily writing habit app.

This is day 1 writing. The user wrote a self-introduction on day 0. Generate a prompt that helps them clarify or expand something they already shared.

RULES:
- Keep prompts to 2-3 sentences maximum.
- Ask for a concrete detail, example, memory, or specific reason.
- Stay on the same topic from the user's intro; do not switch topics.
- NEVER ask a yes/no question.
- Be personal without being invasive.`;

export const DAY_0_WELCOME_TEXT = {
  title: "How This Works",
  body: `**How This Works**

This app works like this. Every day, you'll read something short. Two days later, you'll write about it from memory — in your own words. That's it.

Reading fills your mind. Writing empties it. The gap in between is where ideas form.

There's a concept in cognitive science called the *spacing effect*. When you encounter an idea and then revisit it after a delay, your brain has to work harder to reconstruct it. That effort — that productive struggle — is what transforms passive consumption into genuine understanding. You don't just remember the idea better. You make it yours.

Most of what we read vanishes within hours. Not because the ideas weren't good, but because we never gave our brains a reason to hold onto them. We scroll, we skim, we nod along, and then the next thing pushes the last thing out. The conveyor belt never stops.

Writing is the antidote. When you sit down to write about something you read two days ago, you discover what you actually absorbed versus what you only thought you absorbed. The gaps surprise you. But so do the connections — the moments where the idea merged with something already in your head and became something new.

This isn't about producing polished essays. It's about *thinking on paper*. Some days you'll write two sentences. Other days, something will pour out of you that you didn't know was in there. Both are good. The only metric that matters is whether you showed up.

The readings we'll give you are curated to your interests. They're short — a few minutes to read. The writing prompts aren't quizzes. They're invitations to think. They'll ask you to connect what you read to what you've lived.

Here's the rhythm: read today, let it sit, write about it in two days. Meanwhile, tomorrow brings a new reading. The cycle overlaps. Your mind is always holding multiple threads, weaving them together in the background.

Today, read this. Tomorrow, you'll write.`,
};

export const DAY_0_WRITE_PROMPT =
  "Tell us about yourself. What's your name? What do you do? Why do you want to write? What topics interest you? Write freely — this helps the app find readings you'll care about.";

export const DAY_1_PROMPT_TEMPLATE = `The user just started using Better Writer and wrote this self-introduction on day 0.

Generate one writing prompt that clarifies or expands something they already said. Ask for specifics, an example, or a personal story that opens the idea further. Do not change the topic.

User's introduction:
{userIntro}`;
