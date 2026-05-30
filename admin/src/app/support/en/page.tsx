import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Support — Bisawtak",
  description:
    "Get help with Bisawtak: in-app contact, email support, and typical response times.",
};

const SUPPORT_EMAIL = "support@neojeen.com";

export default function SupportEn() {
  return (
    <div className="min-h-screen bg-gray-50" dir="ltr">
      <header className="bg-white border-b border-gray-200">
        <div className="max-w-3xl mx-auto px-6 py-4 flex items-center justify-between">
          <Link href="/" className="text-xl font-bold text-gray-900">
            Bisawtak
          </Link>
          <Link href="/support" className="text-sm text-blue-600 hover:underline">
            العربية
          </Link>
        </div>
      </header>

      <main className="max-w-3xl mx-auto px-6 py-10">
        <h1 className="text-3xl font-bold text-gray-900 mb-2">Support</h1>
        <p className="text-gray-700 mb-8">We&apos;re here to help.</p>

        <Section title="📱 In-App">
          <p>
            Open <b>Bisawtak</b> → Account → <b>Contact us</b>. You&apos;ll find a
            form to send your message, and replies appear in the same place.
          </p>
        </Section>

        <Section title="📧 Email">
          <p>
            <a
              href={`mailto:${SUPPORT_EMAIL}`}
              className="text-blue-600 hover:underline"
            >
              {SUPPORT_EMAIL}
            </a>
          </p>
        </Section>

        <Section title="📚 FAQ">
          <ul className="list-disc ps-6 space-y-2">
            <li>
              <b>How do I delete my account?</b> Account → Delete Account
              permanently (identity confirmation required).
            </li>
            <li>
              <b>Which formats are supported?</b> MP3, M4A, WAV, OGG, FLAC, AAC,
              WebM, MP4 (audio).
            </li>
            <li>
              <b>Why is my audio trimmed?</b> The free plan is limited to 30
              seconds per file. Upgrade to a paid plan to remove the limit.
            </li>
            <li>
              <b>Is my audio safe?</b> Yes — it is deleted from the server right
              after processing. Only the resulting text is saved to your account.
            </li>
          </ul>
        </Section>

        <Section title="⏱️ Response Time">
          <p>We reply within 24–48 hours on business days.</p>
        </Section>

        <div className="mt-10 pt-6 border-t border-gray-200 text-sm text-gray-500 flex justify-between">
          <Link href="/" className="text-blue-600 hover:underline">
            ← Home
          </Link>
          <Link href="/support" className="text-blue-600 hover:underline">
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
