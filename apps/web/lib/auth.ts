/**
 * JWT-based authentication using HMAC-SHA256 via Web Crypto.
 * Zero external dependencies. Edge-runtime compatible.
 */

const TOKEN_EXPIRY_SECONDS = 30 * 24 * 60 * 60; // 30 days

export class AuthError extends Error {
  readonly status = 401;
  constructor(message = "Unauthorized") {
    super(message);
    this.name = "AuthError";
  }
}

// ---------------------------------------------------------------------------
// Base64url helpers
// ---------------------------------------------------------------------------

function base64urlEncode(data: Uint8Array): string {
  let binary = "";
  for (const byte of data) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64urlDecode(str: string): Uint8Array {
  const padded = str.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

// ---------------------------------------------------------------------------
// Crypto key (cached)
// ---------------------------------------------------------------------------

let cachedKey: CryptoKey | null = null;

function getSecret(): string {
  const secret = process.env.AUTH_SECRET;
  if (!secret) {
    throw new Error("AUTH_SECRET environment variable is not set");
  }
  return secret;
}

async function getSigningKey(): Promise<CryptoKey> {
  if (cachedKey) return cachedKey;
  const secret = getSecret();
  const encoder = new TextEncoder();
  cachedKey = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
  return cachedKey;
}

// ---------------------------------------------------------------------------
// JWT sign / verify
// ---------------------------------------------------------------------------

interface JWTPayload {
  sub: string;
  iat: number;
  exp: number;
}

export async function signJWT(userId: string): Promise<{ token: string; expiresAt: string }> {
  const now = Math.floor(Date.now() / 1000);
  const exp = now + TOKEN_EXPIRY_SECONDS;

  const header = { alg: "HS256", typ: "JWT" };
  const payload: JWTPayload = { sub: userId, iat: now, exp };

  const encoder = new TextEncoder();
  const headerB64 = base64urlEncode(encoder.encode(JSON.stringify(header)));
  const payloadB64 = base64urlEncode(encoder.encode(JSON.stringify(payload)));
  const signingInput = `${headerB64}.${payloadB64}`;

  const key = await getSigningKey();
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(signingInput));

  const token = `${signingInput}.${base64urlEncode(new Uint8Array(signature))}`;
  const expiresAt = new Date(exp * 1000).toISOString();

  return { token, expiresAt };
}

export async function verifyJWT(token: string): Promise<JWTPayload> {
  const parts = token.split(".");
  if (parts.length !== 3) {
    throw new AuthError("Malformed token");
  }

  const [headerB64, payloadB64, signatureB64] = parts;
  const signingInput = `${headerB64}.${payloadB64}`;
  const signature = base64urlDecode(signatureB64);

  const key = await getSigningKey();
  const encoder = new TextEncoder();
  const valid = await crypto.subtle.verify(
    "HMAC",
    key,
    signature.buffer as ArrayBuffer,
    encoder.encode(signingInput),
  );

  if (!valid) {
    throw new AuthError("Invalid token signature");
  }

  const payload: JWTPayload = JSON.parse(
    new TextDecoder().decode(base64urlDecode(payloadB64)),
  );

  const now = Math.floor(Date.now() / 1000);
  if (payload.exp < now) {
    throw new AuthError("Token expired");
  }

  if (!payload.sub) {
    throw new AuthError("Token missing subject");
  }

  return payload;
}

// ---------------------------------------------------------------------------
// Request helpers
// ---------------------------------------------------------------------------

export async function requireUserId(request: Request): Promise<string> {
  const auth = request.headers.get("Authorization");
  if (!auth?.startsWith("Bearer ")) {
    throw new AuthError("Missing Authorization header");
  }

  const token = auth.slice(7).trim();
  if (!token) {
    throw new AuthError("Empty token");
  }

  const payload = await verifyJWT(token);
  return payload.sub;
}
