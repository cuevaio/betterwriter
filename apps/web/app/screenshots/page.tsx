"use client";

import { toPng } from "html-to-image";
import { useCallback, useEffect, useRef, useState } from "react";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const IPHONE_W = 1320;
const IPHONE_H = 2868;

const IPHONE_SIZES = [
  { label: '6.9"', w: 1320, h: 2868 },
  { label: '6.5"', w: 1284, h: 2778 },
] as const;

// Mockup measurements (from skill)
const MK_W = 1022;
const MK_H = 2082;
const SC_L = (52 / MK_W) * 100;
const SC_T = (46 / MK_H) * 100;
const SC_W = (918 / MK_W) * 100;
const SC_H = (1990 / MK_H) * 100;
const SC_RX = (126 / 918) * 100;
const SC_RY = (126 / 1990) * 100;

const SCREENSHOT_BASE = "/screenshots";

const SERIF = "Georgia, 'Times New Roman', serif";
const SANS =
  "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif";

// ---------------------------------------------------------------------------
// Shared components
// ---------------------------------------------------------------------------

function Phone({
  src,
  alt,
  style,
}: {
  src: string;
  alt: string;
  style?: React.CSSProperties;
}) {
  return (
    <div
      style={{
        position: "relative",
        aspectRatio: `${MK_W}/${MK_H}`,
        ...style,
      }}
    >
      {/* biome-ignore lint/performance/noImgElement: html-to-image requires raw img tags */}
      <img
        src="/mockup.png"
        alt=""
        style={{ display: "block", width: "100%", height: "100%" }}
        draggable={false}
      />
      <div
        style={{
          position: "absolute",
          zIndex: 10,
          overflow: "hidden",
          left: `${SC_L}%`,
          top: `${SC_T}%`,
          width: `${SC_W}%`,
          height: `${SC_H}%`,
          borderRadius: `${SC_RX}% / ${SC_RY}%`,
        }}
      >
        {/* biome-ignore lint/performance/noImgElement: html-to-image requires raw img tags */}
        <img
          src={src}
          alt={alt}
          style={{
            display: "block",
            width: "100%",
            height: "100%",
            objectFit: "cover",
            objectPosition: "top",
          }}
          draggable={false}
          onError={(e) => {
            // Show gray placeholder if image is missing
            const target = e.currentTarget;
            target.style.display = "none";
            if (target.parentElement) {
              target.parentElement.style.background = "#888";
              target.parentElement.style.display = "flex";
              target.parentElement.style.alignItems = "center";
              target.parentElement.style.justifyContent = "center";
            }
          }}
        />
      </div>
    </div>
  );
}

function Caption({
  label,
  headline,
  canvasW,
  light = false,
  align = "center",
}: {
  label: string;
  headline: React.ReactNode;
  canvasW: number;
  light?: boolean;
  align?: "center" | "left" | "right";
}) {
  const fg = light ? "#ffffff" : "#000000";
  const secondary = light ? "rgba(255,255,255,0.5)" : "#666666";
  return (
    <div style={{ textAlign: align }}>
      <div
        style={{
          fontSize: canvasW * 0.028,
          fontWeight: 600,
          letterSpacing: "0.15em",
          textTransform: "uppercase",
          color: secondary,
          marginBottom: canvasW * 0.025,
          fontFamily: SANS,
        }}
      >
        {label}
      </div>
      <div
        style={{
          fontSize: canvasW * 0.09,
          fontWeight: 700,
          lineHeight: 1.05,
          color: fg,
          fontFamily: SERIF,
          letterSpacing: "-0.02em",
        }}
      >
        {headline}
      </div>
    </div>
  );
}

function BWIcon({
  size,
  invertColors = false,
}: {
  size: number;
  invertColors?: boolean;
}) {
  const bg = invertColors ? "#ffffff" : "#000000";
  const fg = invertColors ? "#000000" : "#ffffff";
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 512 512"
      xmlns="http://www.w3.org/2000/svg"
      role="img"
      aria-label="Better Writer"
    >
      <title>Better Writer</title>
      <rect width="512" height="512" rx="64" fill={bg} />
      <text
        x="256"
        y="340"
        fontFamily={SERIF}
        fontSize="256"
        fontWeight="700"
        fill={fg}
        textAnchor="middle"
        letterSpacing="-8"
      >
        BW
      </text>
    </svg>
  );
}

// ---------------------------------------------------------------------------
// Slide components
// ---------------------------------------------------------------------------

interface SlideProps {
  canvasW: number;
  canvasH: number;
}

// Slide 1: Hero — white bg, icon top-center, phone centered bottom
function Slide1({ canvasW, canvasH }: SlideProps) {
  return (
    <div
      style={{
        width: canvasW,
        height: canvasH,
        background: "#ffffff",
        position: "relative",
        overflow: "hidden",
        fontFamily: SERIF,
      }}
    >
      {/* Icon */}
      <div
        style={{
          position: "absolute",
          top: canvasH * 0.06,
          left: "50%",
          transform: "translateX(-50%)",
        }}
      >
        <BWIcon size={canvasW * 0.12} />
      </div>

      {/* Caption */}
      <div
        style={{
          position: "absolute",
          top: canvasH * 0.12,
          left: "50%",
          transform: "translateX(-50%)",
          width: canvasW * 0.85,
        }}
      >
        <Caption
          label="Daily Practice"
          headline={
            <>
              Read. Remember.
              <br />
              Write.
            </>
          }
          canvasW={canvasW}
        />
      </div>

      {/* Phone */}
      <Phone
        src={`${SCREENSHOT_BASE}/read.png`}
        alt="Reading screen"
        style={{
          position: "absolute",
          bottom: 0,
          left: "50%",
          transform: "translateX(-50%) translateY(12%)",
          width: "84%",
        }}
      />
    </div>
  );
}

// Slide 2: Differentiator — black bg, phone right-offset, caption left
function Slide2({ canvasW, canvasH }: SlideProps) {
  return (
    <div
      style={{
        width: canvasW,
        height: canvasH,
        background: "#000000",
        position: "relative",
        overflow: "hidden",
        fontFamily: SERIF,
      }}
    >
      {/* Caption — left-aligned */}
      <div
        style={{
          position: "absolute",
          top: canvasH * 0.1,
          left: canvasW * 0.08,
          width: canvasW * 0.7,
        }}
      >
        <Caption
          label="The Method"
          headline={
            <>
              Two days later,
              <br />
              write what stuck.
            </>
          }
          canvasW={canvasW}
          light
          align="left"
        />
      </div>

      {/* Phone — right offset */}
      <Phone
        src={`${SCREENSHOT_BASE}/write-empty.png`}
        alt="Writing prompt screen"
        style={{
          position: "absolute",
          bottom: 0,
          right: canvasW * -0.04,
          transform: "translateY(10%) rotate(2deg)",
          width: "82%",
        }}
      />
    </div>
  );
}

// Slide 3: Reading feature — white bg, phone center-left, caption upper-right
function Slide3({ canvasW, canvasH }: SlideProps) {
  return (
    <div
      style={{
        width: canvasW,
        height: canvasH,
        background: "#ffffff",
        position: "relative",
        overflow: "hidden",
        fontFamily: SERIF,
      }}
    >
      {/* Caption — right-aligned */}
      <div
        style={{
          position: "absolute",
          top: canvasH * 0.08,
          right: canvasW * 0.08,
          width: canvasW * 0.75,
        }}
      >
        <Caption
          label="Reading"
          headline={
            <>
              No scrolling.
              <br />
              No choosing.
              <br />
              Just read.
            </>
          }
          canvasW={canvasW}
          align="right"
        />
      </div>

      {/* Thin editorial rule */}
      <div
        style={{
          position: "absolute",
          top: canvasH * 0.28,
          right: canvasW * 0.08,
          width: canvasW * 0.35,
          height: 1,
          background: "#000000",
          opacity: 0.15,
        }}
      />

      {/* Phone — slightly left of center */}
      <Phone
        src={`${SCREENSHOT_BASE}/read.png`}
        alt="Reading experience"
        style={{
          position: "absolute",
          bottom: 0,
          left: "50%",
          transform: "translateX(-55%) translateY(14%)",
          width: "82%",
        }}
      />
    </div>
  );
}

// Slide 4: Writing feature — black bg, two phones layered
function Slide4({ canvasW, canvasH }: SlideProps) {
  return (
    <div
      style={{
        width: canvasW,
        height: canvasH,
        background: "#000000",
        position: "relative",
        overflow: "hidden",
        fontFamily: SERIF,
      }}
    >
      {/* Caption — centered top */}
      <div
        style={{
          position: "absolute",
          top: canvasH * 0.07,
          left: "50%",
          transform: "translateX(-50%)",
          width: canvasW * 0.85,
        }}
      >
        <Caption
          label="Writing"
          headline={
            <>
              Write from memory.
              <br />
              Not from a blank page.
            </>
          }
          canvasW={canvasW}
          light
        />
      </div>

      {/* Back phone — reading (faded, rotated) */}
      <Phone
        src={`${SCREENSHOT_BASE}/read.png`}
        alt="Reading screen"
        style={{
          position: "absolute",
          bottom: 0,
          left: canvasW * -0.08,
          transform: "translateY(15%) rotate(-4deg)",
          width: "65%",
          opacity: 0.45,
        }}
      />

      {/* Front phone — writing */}
      <Phone
        src={`${SCREENSHOT_BASE}/write.png`}
        alt="Writing screen"
        style={{
          position: "absolute",
          bottom: 0,
          right: canvasW * -0.04,
          transform: "translateY(10%)",
          width: "82%",
        }}
      />
    </div>
  );
}

// Slide 5: Progress — white bg, phone centered high
function Slide5({ canvasW, canvasH }: SlideProps) {
  return (
    <div
      style={{
        width: canvasW,
        height: canvasH,
        background: "#ffffff",
        position: "relative",
        overflow: "hidden",
        fontFamily: SERIF,
      }}
    >
      {/* Caption */}
      <div
        style={{
          position: "absolute",
          top: canvasH * 0.08,
          left: "50%",
          transform: "translateX(-50%)",
          width: canvasW * 0.85,
        }}
      >
        <Caption
          label="Your Progress"
          headline={
            <>
              Every day
              <br />
              leaves a mark.
            </>
          }
          canvasW={canvasW}
        />
      </div>

      {/* Phone — centered, positioned higher */}
      <Phone
        src={`${SCREENSHOT_BASE}/done.png`}
        alt="Progress and stats"
        style={{
          position: "absolute",
          bottom: 0,
          left: "50%",
          transform: "translateX(-50%) translateY(8%)",
          width: "84%",
        }}
      />
    </div>
  );
}

// Slide 6: Closing — black bg, no phone, icon + wordmark + headline
function Slide6({ canvasW, canvasH }: SlideProps) {
  return (
    <div
      style={{
        width: canvasW,
        height: canvasH,
        background: "#000000",
        position: "relative",
        overflow: "hidden",
        fontFamily: SERIF,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      {/* Icon */}
      <div style={{ marginBottom: canvasW * 0.06 }}>
        <BWIcon size={canvasW * 0.18} invertColors />
      </div>

      {/* Wordmark */}
      <div
        style={{
          fontSize: canvasW * 0.058,
          fontWeight: 400,
          letterSpacing: "0.08em",
          color: "rgba(255,255,255,0.5)",
          fontFamily: SERIF,
          marginBottom: canvasW * 0.08,
        }}
      >
        betterwriter
      </div>

      {/* Headline */}
      <div
        style={{
          fontSize: canvasW * 0.095,
          fontWeight: 700,
          lineHeight: 1.05,
          color: "#ffffff",
          fontFamily: SERIF,
          letterSpacing: "-0.02em",
          textAlign: "center",
          padding: `0 ${canvasW * 0.1}px`,
        }}
      >
        Build a mind
        <br />
        that writes.
      </div>

      {/* Tagline at bottom */}
      <div
        style={{
          position: "absolute",
          bottom: canvasH * 0.08,
          fontSize: canvasW * 0.03,
          fontWeight: 600,
          letterSpacing: "0.15em",
          textTransform: "uppercase",
          color: "rgba(255,255,255,0.35)",
          fontFamily: SANS,
        }}
      >
        Read. Remember. Write.
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Screenshot registry
// ---------------------------------------------------------------------------

const SCREENSHOTS: {
  id: string;
  label: string;
  component: React.FC<SlideProps>;
}[] = [
  { id: "hero", label: "Hero", component: Slide1 },
  { id: "method", label: "The Method", component: Slide2 },
  { id: "reading", label: "Reading", component: Slide3 },
  { id: "writing", label: "Writing", component: Slide4 },
  { id: "progress", label: "Progress", component: Slide5 },
  { id: "closing", label: "Closing", component: Slide6 },
];

// ---------------------------------------------------------------------------
// Preview card with ResizeObserver scaling
// ---------------------------------------------------------------------------

function ScreenshotPreview({
  slideIndex,
  canvasW,
  canvasH,
  onExport,
  exporting,
}: {
  slideIndex: number;
  canvasW: number;
  canvasH: number;
  onExport: (index: number) => void;
  exporting: boolean;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(0.15);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const observer = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const containerW = entry.contentRect.width;
        setScale(containerW / canvasW);
      }
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, [canvasW]);

  const slide = SCREENSHOTS[slideIndex];
  const SlideComponent = slide.component;

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        gap: 8,
      }}
    >
      <div
        ref={containerRef}
        style={{
          width: "100%",
          aspectRatio: `${canvasW}/${canvasH}`,
          overflow: "hidden",
          borderRadius: 8,
          border: "1px solid #e0e0e0",
          position: "relative",
          background: "#f5f5f5",
        }}
      >
        <div
          style={{
            transform: `scale(${scale})`,
            transformOrigin: "top left",
            width: canvasW,
            height: canvasH,
          }}
        >
          <SlideComponent canvasW={canvasW} canvasH={canvasH} />
        </div>
      </div>
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
        }}
      >
        <span
          style={{
            fontSize: 13,
            fontWeight: 600,
            color: "#333",
            fontFamily: SANS,
          }}
        >
          {slide.label}
        </span>
        <button
          type="button"
          onClick={() => onExport(slideIndex)}
          disabled={exporting}
          style={{
            fontSize: 12,
            padding: "4px 12px",
            border: "1px solid #ccc",
            borderRadius: 4,
            background: exporting ? "#eee" : "#fff",
            cursor: exporting ? "default" : "pointer",
            fontFamily: SANS,
          }}
        >
          Export
        </button>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------

export default function ScreenshotsPage() {
  const [sizeIndex, setSizeIndex] = useState(0);
  const [exporting, setExporting] = useState(false);
  const offscreenRef = useRef<HTMLDivElement>(null);

  const selectedSize = IPHONE_SIZES[sizeIndex];
  const W = selectedSize.w;
  const H = selectedSize.h;

  const exportSlide = useCallback(
    async (index: number) => {
      const container = offscreenRef.current;
      if (!container) return;

      setExporting(true);
      try {
        // Create temporary element for this specific slide
        const slideEl = document.createElement("div");
        slideEl.style.width = `${IPHONE_W}px`;
        slideEl.style.height = `${IPHONE_H}px`;
        slideEl.style.position = "absolute";
        slideEl.style.left = "-9999px";
        slideEl.style.fontFamily = SERIF;
        document.body.appendChild(slideEl);

        // Render the slide into the temp element
        const { createRoot } = await import("react-dom/client");
        const SlideComponent = SCREENSHOTS[index].component;
        const root = createRoot(slideEl);

        await new Promise<void>((resolve) => {
          root.render(<SlideComponent canvasW={IPHONE_W} canvasH={IPHONE_H} />);
          // Give React time to render + images to load
          setTimeout(resolve, 500);
        });

        // Move on-screen for capture
        slideEl.style.left = "0px";
        slideEl.style.opacity = "1";
        slideEl.style.zIndex = "-1";

        const opts = {
          width: IPHONE_W,
          height: IPHONE_H,
          pixelRatio: 1,
          cacheBust: true,
        };

        // Double-call trick: first warms fonts/images, second is clean
        await toPng(slideEl, opts);
        const dataUrl = await toPng(slideEl, opts);

        // Move back off-screen
        slideEl.style.left = "-9999px";
        slideEl.style.opacity = "";
        slideEl.style.zIndex = "";

        // Draw through a canvas to strip alpha channel and resize if needed
        const finalUrl = await new Promise<string>((resolve) => {
          const img = new Image();
          img.onload = () => {
            const canvas = document.createElement("canvas");
            canvas.width = W;
            canvas.height = H;
            const ctx = canvas.getContext("2d");
            if (ctx) {
              // Fill with white first to eliminate any transparency
              ctx.fillStyle = "#ffffff";
              ctx.fillRect(0, 0, W, H);
              ctx.drawImage(img, 0, 0, W, H);
              resolve(canvas.toDataURL("image/png"));
            } else {
              resolve(dataUrl);
            }
          };
          img.src = dataUrl;
        });

        // Download
        const padded = String(index + 1).padStart(2, "0");
        const link = document.createElement("a");
        link.download = `${padded}-${SCREENSHOTS[index].id}-${W}x${H}.png`;
        link.href = finalUrl;
        link.click();

        // Cleanup
        root.unmount();
        document.body.removeChild(slideEl);
      } catch (err) {
        console.error("Export failed:", err);
      } finally {
        setExporting(false);
      }
    },
    [W, H]
  );

  const exportAll = useCallback(async () => {
    setExporting(true);
    for (let i = 0; i < SCREENSHOTS.length; i++) {
      await exportSlide(i);
      // Delay between exports
      await new Promise((r) => setTimeout(r, 300));
    }
    setExporting(false);
  }, [exportSlide]);

  return (
    <div
      style={{
        minHeight: "100vh",
        background: "#f0f0f0",
        fontFamily: SANS,
        padding: 24,
      }}
    >
      {/* Toolbar */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          marginBottom: 24,
          flexWrap: "wrap",
          gap: 12,
        }}
      >
        <h1
          style={{
            fontSize: 20,
            fontWeight: 700,
            color: "#111",
            margin: 0,
          }}
        >
          betterwriter — App Store Screenshots
        </h1>

        <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
          {/* Size toggle */}
          {IPHONE_SIZES.map((s, i) => (
            <button
              type="button"
              key={s.label}
              onClick={() => setSizeIndex(i)}
              style={{
                fontSize: 13,
                padding: "6px 14px",
                border: sizeIndex === i ? "1.5px solid #111" : "1px solid #ccc",
                borderRadius: 4,
                background: sizeIndex === i ? "#111" : "#fff",
                color: sizeIndex === i ? "#fff" : "#333",
                fontWeight: sizeIndex === i ? 600 : 400,
                cursor: "pointer",
                fontFamily: SANS,
              }}
            >
              {s.label}
            </button>
          ))}

          <div
            style={{
              width: 1,
              height: 24,
              background: "#ddd",
              margin: "0 4px",
            }}
          />

          {/* Export All */}
          <button
            type="button"
            onClick={exportAll}
            disabled={exporting}
            style={{
              fontSize: 13,
              fontWeight: 600,
              padding: "6px 20px",
              border: "none",
              borderRadius: 4,
              background: exporting ? "#999" : "#111",
              color: "#fff",
              cursor: exporting ? "default" : "pointer",
              fontFamily: SANS,
            }}
          >
            {exporting ? "Exporting..." : "Export All"}
          </button>
        </div>
      </div>

      {/* Preview grid */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fill, minmax(220px, 1fr))",
          gap: 20,
        }}
      >
        {SCREENSHOTS.map((s, i) => (
          <ScreenshotPreview
            key={s.id}
            slideIndex={i}
            canvasW={IPHONE_W}
            canvasH={IPHONE_H}
            onExport={exportSlide}
            exporting={exporting}
          />
        ))}
      </div>

      {/* Offscreen container (for potential future use) */}
      <div
        ref={offscreenRef}
        style={{ position: "absolute", left: -9999, top: 0 }}
      />
    </div>
  );
}
