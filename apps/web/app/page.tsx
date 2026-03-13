export default function Home() {
  return (
    <main
      style={{
        minHeight: "100dvh",
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        alignItems: "center",
        padding: "48px 24px 80px",
        maxWidth: 640,
        margin: "0 auto",
      }}
    >
      <div style={{ marginBottom: 24 }}>
        <svg
          width="64"
          height="64"
          viewBox="0 0 512 512"
          xmlns="http://www.w3.org/2000/svg"
          role="img"
          aria-label="Better Writer"
        >
          <rect width="512" height="512" rx="64" fill="var(--foreground)" />
          <text
            x="256"
            y="340"
            fontFamily="Georgia, 'Times New Roman', serif"
            fontSize="256"
            fontWeight="700"
            fill="var(--background)"
            textAnchor="middle"
            letterSpacing="-8"
          >
            BW
          </text>
        </svg>
      </div>

      <h1
        style={{
          fontFamily: "Georgia, 'Times New Roman', serif",
          fontSize: "clamp(2rem, 5vw, 3rem)",
          fontWeight: 400,
          letterSpacing: "-0.02em",
          marginBottom: 32,
          textAlign: "center",
        }}
      >
        Read. Remember. Write.
      </h1>

      <p
        style={{
          fontSize: "1.125rem",
          lineHeight: 1.7,
          color: "var(--secondary)",
          textAlign: "center",
          marginBottom: 48,
          maxWidth: 480,
        }}
      >
        Every day, read something short. Two days later, write about it from
        memory. The gap in between is where ideas form.
      </p>

      <div
        style={{
          display: "flex",
          flexDirection: "column",
          gap: 24,
          width: "100%",
          maxWidth: 400,
          marginBottom: 64,
        }}
      >
        <Step
          number={1}
          title="Read"
          description="A curated text, chosen for you. A few minutes."
        />
        <Step
          number={2}
          title="Write"
          description="Two days later, write what stuck. In your own words."
        />
        <Step
          number={3}
          title="Repeat"
          description="That's the whole app. Show up, and ideas compound."
        />
      </div>

      <a
        href="https://apps.apple.com"
        style={{
          display: "inline-block",
          padding: "16px 48px",
          border: "1.5px solid var(--foreground)",
          color: "var(--foreground)",
          textDecoration: "none",
          fontSize: "0.875rem",
          fontWeight: 600,
          letterSpacing: "0.1em",
          textTransform: "uppercase",
        }}
      >
        Coming Soon
      </a>

      <footer
        style={{
          position: "fixed",
          bottom: 0,
          left: 0,
          right: 0,
          display: "flex",
          justifyContent: "center",
          gap: 24,
          padding: "16px 24px",
        }}
      >
        <a
          href="/privacy"
          style={{
            fontSize: "0.75rem",
            color: "var(--secondary)",
            textDecoration: "none",
          }}
        >
          Privacy
        </a>
        <a
          href="/terms"
          style={{
            fontSize: "0.75rem",
            color: "var(--secondary)",
            textDecoration: "none",
          }}
        >
          Terms
        </a>
        <a
          href="/support"
          style={{
            fontSize: "0.75rem",
            color: "var(--secondary)",
            textDecoration: "none",
          }}
        >
          Support
        </a>
      </footer>
    </main>
  );
}

function Step({
  number,
  title,
  description,
}: {
  number: number;
  title: string;
  description: string;
}) {
  return (
    <div style={{ display: "flex", gap: 16, alignItems: "baseline" }}>
      <span
        style={{
          fontFamily: "Georgia, serif",
          fontSize: "1.5rem",
          fontWeight: 400,
          opacity: 0.3,
          minWidth: 24,
        }}
      >
        {number}
      </span>
      <div>
        <span style={{ fontWeight: 600, fontSize: "1rem" }}>{title}</span>
        <span
          style={{
            color: "var(--secondary)",
            fontSize: "0.95rem",
            marginLeft: 8,
          }}
        >
          {description}
        </span>
      </div>
    </div>
  );
}
