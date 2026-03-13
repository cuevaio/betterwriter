/**
 * Stream a constant string in small word-sized chunks,
 * mimicking the feel of AI-generated streaming.
 */
export async function streamConstant(
  text: string,
  onDelta: (delta: string) => void | Promise<void>,
  chunkSize = 4,
): Promise<void> {
  const parts = text.split(/(\s+)/);
  let buffer = "";
  let wordCount = 0;

  for (const part of parts) {
    buffer += part;
    if (/\S/.test(part)) wordCount++;
    if (wordCount >= chunkSize) {
      await onDelta(buffer);
      buffer = "";
      wordCount = 0;
    }
  }

  if (buffer) await onDelta(buffer);
}
