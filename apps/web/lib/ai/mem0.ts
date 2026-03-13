import { addMemories, retrieveMemories } from "@mem0/vercel-ai-provider";

const DEFAULT_MODEL = "openai/gpt-oss-120b";

const mem0ApiKey = process.env.MEM0_API_KEY;

export function aiModel(_userId: string) {
  return process.env.MEM0_MODEL ?? DEFAULT_MODEL;
}

export async function retrieveMemoryContext(userId: string, prompt: string): Promise<string> {
  if (!mem0ApiKey || !prompt.trim()) return "";

  try {
    const context = await retrieveMemories(prompt, {
      user_id: userId,
      mem0ApiKey,
    });

    return typeof context === "string" ? context : "";
  } catch {
    return "";
  }
}

export function withMemorySystem(system: string, memoryContext: string): string {
  if (!memoryContext.trim()) return system;
  return `${system}\n\n${memoryContext}`;
}

export async function addUserInputMemory(userId: string, text: string): Promise<void> {
  if (!text.trim()) return;

  try {
    await addMemories(
      [
        {
          role: "user",
          content: [{ type: "text", text }],
        },
      ],
      {
        user_id: userId,
        ...(mem0ApiKey ? { mem0ApiKey } : {}),
      }
    );
  } catch {
    return;
  }
}
