import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Privacy Policy — Bisawtak",
  description:
    "How Bisawtak handles your data: voice recordings, account info, usage stats, and third-party services.",
};

const LAST_UPDATED = "May 16, 2026";
const SUPPORT_EMAIL = "support@neojeen.com";

export default function PrivacyPolicyEn() {
  return (
    <div dir="ltr" lang="en" className="min-h-screen bg-gray-50">
      <header className="bg-white border-b border-gray-200">
        <div className="max-w-3xl mx-auto px-6 py-4 flex items-center justify-between">
          <Link href="/" className="text-xl font-bold text-gray-900">
            Bisawtak
          </Link>
          <Link
            href="/privacy"
            className="text-sm text-blue-600 hover:underline"
          >
            عربي
          </Link>
        </div>
      </header>

      <main className="max-w-3xl mx-auto px-6 py-10">
        <h1 className="text-3xl font-bold text-gray-900 mb-2">
          Privacy Policy
        </h1>
        <p className="text-sm text-gray-500 mb-8">
          Last updated: {LAST_UPDATED}
        </p>

        <Section title="Introduction">
          <p>
            <b>Bisawtak</b> (بصوتك) is a speech-to-text service for Arabic
            and 30+ other languages. The app was originally designed to help
            deaf and hard-of-hearing users, and protecting your privacy is
            a core part of how we operate.
          </p>
          <p>
            This policy explains what data we collect, why we collect it,
            how we use it, and who has access to it. By using the app, you
            agree to the terms below.
          </p>
        </Section>

        <Section title="1. Data We Collect">
          <h3 className="font-semibold text-gray-800 mt-3 mb-1">
            (a) Account data
          </h3>
          <ul className="list-disc pl-6 space-y-1">
            <li>Full name, username, and email (if you register).</li>
            <li>
              Identity provider ID if you sign in with Google or Apple
              (we never store their passwords).
            </li>
            <li>
              Password — stored as a bcrypt hash if you register with
              email/password.
            </li>
          </ul>

          <h3 className="font-semibold text-gray-800 mt-4 mb-1">
            (b) Audio files
          </h3>
          <ul className="list-disc pl-6 space-y-1">
            <li>
              Recordings you upload or capture in-app are sent to a
              transcription provider, then deleted from our servers as soon
              as processing completes.
            </li>
            <li>
              We do not keep a copy of the audio after transcription. The
              resulting text is stored locally on your device (inside the
              app&apos;s SQLite database).
            </li>
          </ul>

          <h3 className="font-semibold text-gray-800 mt-4 mb-1">
            (c) Usage logs
          </h3>
          <ul className="list-disc pl-6 space-y-1">
            <li>
              Request count and duration, detected language, word count,
              provider used — for daily/monthly quota tracking and plan
              status.
            </li>
            <li>
              We do not keep the transcribed text itself on our servers —
              only the numeric stats.
            </li>
          </ul>

          <h3 className="font-semibold text-gray-800 mt-4 mb-1">
            (d) Device &amp; session data
          </h3>
          <ul className="list-disc pl-6 space-y-1">
            <li>
              OS, device model, app version, IP address, login time — for
              security and detecting abusive use.
            </li>
            <li>Crash reports via Firebase Crashlytics.</li>
          </ul>

          <h3 className="font-semibold text-gray-800 mt-4 mb-1">
            (e) Support attachments
          </h3>
          <ul className="list-disc pl-6 space-y-1">
            <li>
              If you attach a screenshot inside a support ticket, it is
              stored on our servers until the issue is resolved. You can
              request its deletion any time.
            </li>
          </ul>
        </Section>

        <Section title="2. Device Permissions">
          <ul className="list-disc pl-6 space-y-1">
            <li>
              <b>Microphone</b>: for in-app recording. We never record in
              the background.
            </li>
            <li>
              <b>Storage / Files</b>: to pick an audio file or screenshot
              from your device.
            </li>
            <li>
              <b>Notifications</b>: to notify you when transcription is
              complete even after you leave the app.
            </li>
            <li>
              <b>Internet</b>: to send audio to transcription providers and
              receive text back.
            </li>
          </ul>
        </Section>

        <Section title="3. Third-Party Services">
          <p>
            When you transcribe an audio file, it is sent to one of the
            following providers (we choose based on your plan and the
            settings at request time):
          </p>
          <ul className="list-disc pl-6 space-y-1">
            <li>
              <b>OpenAI Whisper</b> (runs on our own servers — audio never
              leaves them).
            </li>
            <li>
              <b>Speechmatics</b>, <b>Google Gemini</b>, <b>Groq</b>,{" "}
              <b>AssemblyAI</b> — each has its own privacy policy. Audio is
              deleted from their servers post-transcription per their
              stated policies.
            </li>
            <li>
              <b>Firebase</b> (Google): analytics and crash reports — neither
              audio nor transcribed text is sent.
            </li>
            <li>
              <b>Google Sign-In / Apple Sign-In</b>: authentication only —
              we receive your user ID and email only.
            </li>
            <li>
              <b>Telegram Bot API</b>: for users of the official{" "}
              <span>@bisawtikbot</span> — we receive your Telegram ID and the
              voice message you send.
            </li>
          </ul>
        </Section>

        <Section title="4. Account &amp; Data Deletion">
          <p>
            You can fully delete your account from inside the app:{" "}
            <b>Profile → Delete Account</b>. When you do:
          </p>
          <ul className="list-disc pl-6 space-y-1">
            <li>
              Your account is deactivated and your email/username are
              replaced with anonymized values.
            </li>
            <li>
              We retain an anonymized record for financial audits and to
              prevent repeated abuse.
            </li>
            <li>
              All active sessions are revoked and tokens deleted immediately.
            </li>
          </ul>
          <p className="mt-2">
            Or email{" "}
            <a
              href={`mailto:${SUPPORT_EMAIL}`}
              className="text-blue-600 hover:underline"
            >
              {SUPPORT_EMAIL}
            </a>{" "}
            to request a complete erasure with no residual record.
          </p>
        </Section>

        <Section title="5. Children">
          <p>
            The app is not directed at children under 13, and we do not
            knowingly collect their data. If you learn that a child has
            created an account, contact us and we will delete it.
          </p>
        </Section>

        <Section title="6. Data Security">
          <ul className="list-disc pl-6 space-y-1">
            <li>All communication with our servers uses HTTPS / TLS.</li>
            <li>
              Tokens are stored securely in Keychain on iOS and
              EncryptedSharedPreferences on Android.
            </li>
            <li>
              Passwords are bcrypt-hashed — we can never see them in plain
              text.
            </li>
            <li>
              JWT tokens expire automatically, and you can revoke all
              sessions from inside the app.
            </li>
          </ul>
        </Section>

        <Section title="7. Changes to This Policy">
          <p>
            We may update this policy from time to time. Material changes
            will be communicated inside the app. The date at the top of
            this page reflects the latest update.
          </p>
        </Section>

        <Section title="8. Contact Us">
          <p>
            For any question or request related to this policy:{" "}
            <a
              href={`mailto:${SUPPORT_EMAIL}`}
              className="text-blue-600 hover:underline"
            >
              {SUPPORT_EMAIL}
            </a>
          </p>
        </Section>

        <div className="mt-10 pt-6 border-t border-gray-200 text-sm text-gray-500 flex justify-between">
          <Link href="/" className="text-blue-600 hover:underline">
            ← Home
          </Link>
          <Link href="/privacy" className="text-blue-600 hover:underline">
            النسخة العربية →
          </Link>
        </div>
      </main>
    </div>
  );
}

function Section({
  title,
  children,
}: {
  title: string;
  children: React.ReactNode;
}) {
  return (
    <section className="mb-8">
      <h2 className="text-xl font-bold text-gray-900 mb-3">{title}</h2>
      <div className="text-gray-700 leading-relaxed space-y-2">{children}</div>
    </section>
  );
}
