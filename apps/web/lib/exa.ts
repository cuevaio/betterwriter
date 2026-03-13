interface ExaResult {
  title: string;
  url: string;
  text: string | null;
  publishedDate: string | null;
}

interface ExaSearchResponse {
  results: ExaResult[];
}

export async function searchExa(
  query: string,
  options?: { numResults?: number }
): Promise<ExaResult[]> {
  const res = await fetch("https://api.exa.ai/search", {
    method: "POST",
    headers: {
      "x-api-key": process.env.EXA_API_KEY!,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      query,
      type: "auto",
      numResults: options?.numResults ?? 5,
      contents: {
        text: { maxCharacters: 3000 },
      },
    }),
  });

  if (!res.ok) {
    throw new Error(`Exa search failed: ${res.status} ${res.statusText}`);
  }

  const data: ExaSearchResponse = await res.json();
  return data.results;
}
