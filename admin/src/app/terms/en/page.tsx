import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Terms of Service — Bisawtak",
  description:
    "Bisawtak terms of service: the service, your account, content, plans and subscriptions, and liability.",
};

const LAST_UPDATED = "May 12, 2026";

export default function TermsEn() {
  return (
    <div className="min-h-screen bg-gray-50" dir="ltr">
      <header className="bg-white border-b border-gray-200">
        <div className="max-w-3xl mx-auto px-6 py-4 flex items-center justify-between">
          <Link href="/" className="text-xl font-bold text-gray-900">
            Bisawtak
          </Link>
          <Link href="/terms" className="text-sm text-blue-600 hover:underline">
            العربية
          </Link>
        </div>
      </header>

      <main className="max-w-3xl mx-auto px-6 py-10">
        <h1 className="text-3xl font-bold text-gray-900 mb-2">Terms of Service</h1>
        <p className="text-sm text-gray-500 mb-8">Last updated: {LAST_UPDATED}</p>

        <Section title="1. Acceptance">
          <p>
            By using <b>Bisawtak</b> you agree to these terms.
          </p>
        </Section>

        <Section title="2. Service">
          <p>
            Bisawtak provides speech-to-text conversion using AI. Accuracy is
            high but not 100%.
          </p>
        </Section>

        <Section title="3. Account">
          <p>
            You are responsible for keeping your password secure and for the
            accuracy of the information you provide.
          </p>
        </Section>

        <Section title="4. Content">
          <p>
            You own the audio you upload and the resulting text. Uploading
            unlawful content is prohibited.
          </p>
        </Section>

        <Section title="5. Plans &amp; Subscriptions">
          <p>
            The free plan has daily limits. Paid subscriptions auto-renew until
            cancelled.
          </p>
        </Section>

        <Section title="6. Liability">
          <p>
            The service is provided &quot;as is&quot;. We are not liable for
            damages from reliance on transcription accuracy in sensitive
            decisions.
          </p>
        </Section>

        <Section title="7. Governing Law">
          <p>Governed by the laws of the Arab Republic of Egypt.</p>
        </Section>

        <Section title="8. Contact">
          <p>
            For legal questions:{" "}
            <Link href="/support/en" className="text-blue-600 hover:underline">
              support page
            </Link>
            .
          </p>
        </Section>

        <div className="mt-10 pt-6 border-t border-gray-200 text-sm text-gray-500 flex justify-between">
          <Link href="/" className="text-blue-600 hover:underline">
            ← Home
          </Link>
          <Link href="/terms" className="text-blue-600 hover:underline">
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
