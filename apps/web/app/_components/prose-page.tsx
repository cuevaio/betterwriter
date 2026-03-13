import fs from "fs";
import Link from "next/link";
import path from "path";
import Markdown from "react-markdown";

interface ProsePageProps {
  slug: string;
}

export function ProsePage({ slug }: ProsePageProps) {
  const filePath = path.join(process.cwd(), "content", `${slug}.md`);
  const content = fs.readFileSync(filePath, "utf-8");

  return (
    <main
      style={{
        minHeight: "100dvh",
        maxWidth: 640,
        margin: "0 auto",
        padding: "64px 24px",
      }}
    >
      <Link
        href="/"
        style={{
          display: "inline-block",
          marginBottom: 48,
          fontSize: "0.875rem",
          color: "var(--secondary)",
          textDecoration: "none",
          letterSpacing: "0.05em",
        }}
      >
        ← Better Writer
      </Link>

      <div className="prose">
        <Markdown
          components={{
            h1: ({ children }) => (
              <h1
                style={{
                  fontFamily: "Georgia, 'Times New Roman', serif",
                  fontSize: "clamp(1.75rem, 4vw, 2.25rem)",
                  fontWeight: 400,
                  letterSpacing: "-0.02em",
                  marginBottom: 8,
                  lineHeight: 1.2,
                }}
              >
                {children}
              </h1>
            ),
            h2: ({ children }) => (
              <h2
                style={{
                  fontFamily: "Georgia, 'Times New Roman', serif",
                  fontSize: "1.25rem",
                  fontWeight: 400,
                  letterSpacing: "-0.01em",
                  marginTop: 40,
                  marginBottom: 12,
                }}
              >
                {children}
              </h2>
            ),
            h3: ({ children }) => (
              <h3
                style={{
                  fontSize: "1rem",
                  fontWeight: 600,
                  marginTop: 28,
                  marginBottom: 8,
                }}
              >
                {children}
              </h3>
            ),
            p: ({ children }) => (
              <p
                style={{
                  fontSize: "1rem",
                  lineHeight: 1.75,
                  color: "var(--secondary)",
                  marginBottom: 16,
                }}
              >
                {children}
              </p>
            ),
            a: ({ href, children }) => (
              <a
                href={href}
                style={{
                  color: "var(--foreground)",
                  textUnderlineOffset: 3,
                }}
              >
                {children}
              </a>
            ),
            ul: ({ children }) => (
              <ul
                style={{
                  paddingLeft: 24,
                  marginBottom: 16,
                  color: "var(--secondary)",
                  lineHeight: 1.75,
                }}
              >
                {children}
              </ul>
            ),
            ol: ({ children }) => (
              <ol
                style={{
                  paddingLeft: 24,
                  marginBottom: 16,
                  color: "var(--secondary)",
                  lineHeight: 1.75,
                }}
              >
                {children}
              </ol>
            ),
            li: ({ children }) => (
              <li style={{ marginBottom: 4 }}>{children}</li>
            ),
            hr: () => (
              <hr
                style={{
                  border: "none",
                  borderTop: "1px solid",
                  borderColor: "var(--secondary)",
                  opacity: 0.2,
                  marginTop: 40,
                  marginBottom: 40,
                }}
              />
            ),
            strong: ({ children }) => (
              <strong style={{ color: "var(--foreground)", fontWeight: 600 }}>
                {children}
              </strong>
            ),
            table: ({ children }) => (
              <div style={{ overflowX: "auto", marginBottom: 24 }}>
                <table
                  style={{
                    width: "100%",
                    borderCollapse: "collapse",
                    fontSize: "0.9rem",
                    color: "var(--secondary)",
                  }}
                >
                  {children}
                </table>
              </div>
            ),
            th: ({ children }) => (
              <th
                style={{
                  textAlign: "left",
                  padding: "8px 12px",
                  borderBottom: "1px solid",
                  borderColor: "var(--secondary)",
                  opacity: 1,
                  fontWeight: 600,
                  color: "var(--foreground)",
                  whiteSpace: "nowrap",
                }}
              >
                {children}
              </th>
            ),
            td: ({ children }) => (
              <td
                style={{
                  padding: "8px 12px",
                  borderBottom: "1px solid",
                  borderColor: "var(--secondary)",
                  opacity: 1,
                  verticalAlign: "top",
                }}
              >
                {children}
              </td>
            ),
          }}
        >
          {content}
        </Markdown>
      </div>
    </main>
  );
}
