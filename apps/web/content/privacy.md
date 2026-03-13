# Privacy Policy

**Effective Date:** March 13, 2026
**Operated by:** Anthony Cueva

Better Writer ("the App") is a daily reading and writing habit app. This Privacy Policy explains what data we collect, how we use it, and your rights regarding that data.

---

## 1. What We Collect

Better Writer is designed around data minimization. We collect only what is necessary to provide the service.

### Information you provide

- **Writing text** — The words you write in response to prompts, including your day 0 self-introduction.
- **Reading completion status** — Whether you finished a daily reading.
- **Writing completion status** — Whether you finished a daily writing prompt.

### Information generated automatically

- **Device identifier** — A random UUID generated on your device and stored in the iOS Keychain. This is not tied to your name, email, or Apple ID. It persists across app reinstalls but does not survive device resets.
- **Install date** — The date you first opened the app.
- **Progress data** — Current streak, longest streak, total words written, and onboarding completion status.

### What we do NOT collect

- No email address, name, phone number, or password
- No location or GPS data
- No contacts or photos
- No cookies, browser storage, or tracking pixels
- No analytics or usage telemetry
- No advertising identifiers
- No device fingerprinting

---

## 2. How We Use Your Data

We use the data we collect to:

- **Personalize your experience** — Your writing is analyzed by an AI memory system to understand your interests and preferences, so future readings and prompts are relevant to you.
- **Generate content** — AI models produce daily curated readings and writing prompts tailored to your interests.
- **Track your progress** — Streaks, word counts, and completion status help you maintain your writing habit.
- **Sync across sessions** — Your data is synced between your device and our servers so your progress is preserved.

---

## 3. Third-Party Services

We use the following third-party services to operate the App. Each processes only the minimum data necessary for its function.

| Service | Purpose | Data shared |
|---|---|---|
| **Turso** | Cloud database | Device ID, writing text, progress data |
| **Upstash** | Real-time streaming and background job processing | Device ID, content generation events (expires after 24 hours) |
| **Mem0** | AI memory — extracts your interests and preferences from your writing to personalize future content | Device ID, writing text |
| **Exa** | Article search — finds source material for daily readings | Search queries derived from your interests (no direct writing text) |
| **AI model providers** | Generate curated readings and writing prompts | Your interest profile (from Mem0), relevant context from previous readings |

We do not sell, rent, or share your data with advertisers or data brokers.

---

## 4. Data Storage and Security

- All communication between the App and our servers uses HTTPS encryption.
- Authentication uses signed JSON Web Tokens (JWT) with HMAC-SHA256.
- Your data is stored in a cloud database hosted by Turso.
- Real-time stream data stored in Upstash Redis expires automatically after 24 hours.
- Database records (your entries and profile) are stored indefinitely until you request deletion.

---

## 5. Your Rights

You have the right to:

- **Request deletion** of all your data by emailing [hi@cueva.io](mailto:hi@cueva.io). We will delete your account and all associated data from our database and third-party services within 30 days.
- **Request export** of your data by emailing [hi@cueva.io](mailto:hi@cueva.io). We will provide a copy of your stored data in a machine-readable format.
- **Stop using the service** at any time by deleting the app from your device.

---

## 6. Children's Privacy

Better Writer is not directed at children under the age of 13. We do not knowingly collect personal information from children. If you believe a child has provided us with data, please contact us at [hi@cueva.io](mailto:hi@cueva.io) and we will delete it promptly.

---

## 7. Changes to This Policy

We may update this Privacy Policy from time to time. Changes will be reflected on this page with an updated effective date. Your continued use of the App after changes are posted constitutes acceptance of the revised policy.

---

## 8. Contact

If you have questions about this Privacy Policy or your data, contact us at:

**Email:** [hi@cueva.io](mailto:hi@cueva.io)
