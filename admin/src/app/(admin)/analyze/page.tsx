"use client";

import { useEffect, useRef, useState } from "react";
import { api } from "@/lib/api";
import { toast } from "@/components/toaster";
import { ErrorBoundary } from "@/components/error-boundary";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { formatNumber } from "@/lib/format";
import type { AnalyzeAudioResponse } from "@/lib/types";

function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return "—";
  const units = ["بايت", "ك.ب", "م.ب", "ج.ب"];
  let v = bytes;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  const n = i === 0 ? Math.round(v) : Math.round(v * 10) / 10;
  return `${formatNumber(n)} ${units[i]}`;
}

function formatSeconds(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 0) return "—";
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${formatNumber(m)}:${s.toString().padStart(2, "0")}`;
}

const PUNCT_LABEL: Record<string, string> = {
  comma: "فاصلة",
  period: "نقطة",
  question_mark: "علامة استفهام",
  exclamation_mark: "علامة تعجّب",
  semicolon: "فاصلة منقوطة",
  colon: "نقطتان",
  ellipsis: "نقاط متتابعة",
};

export default function AnalyzePage() {
  return (
    <ErrorBoundary>
      <AnalyzePageBody />
    </ErrorBoundary>
  );
}

function AnalyzePageBody() {
  const [file, setFile] = useState<File | null>(null);
  const [audioUrl, setAudioUrl] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<AnalyzeAudioResponse | null>(null);
  const [dragActive, setDragActive] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  // Revoke the object URL whenever the file changes or component unmounts —
  // otherwise blob URLs leak memory across multiple uploads.
  useEffect(() => {
    if (!file) {
      setAudioUrl(null);
      return;
    }
    const url = URL.createObjectURL(file);
    setAudioUrl(url);
    return () => URL.revokeObjectURL(url);
  }, [file]);

  function pickFile(f: File | null) {
    if (!f) return;
    if (!f.type.startsWith("audio/") && !/\.(mp3|wav|m4a|ogg|opus|flac|webm|aac)$/i.test(f.name)) {
      toast.error("الملف ليس ملف صوتي صالح");
      return;
    }
    setFile(f);
    setResult(null);
  }

  function onDrop(e: React.DragEvent) {
    e.preventDefault();
    setDragActive(false);
    const f = e.dataTransfer.files?.[0];
    if (f) pickFile(f);
  }

  async function analyze() {
    if (!file) return;
    setLoading(true);
    try {
      const fd = new FormData();
      fd.append("file", file);
      const data = await api<AnalyzeAudioResponse>("/admin/analyze-audio", {
        method: "POST",
        body: fd,
      });
      setResult(data);
      toast.success("اكتمل التحليل");
    } catch (e) {
      const msg = e instanceof Error ? e.message : "فشل التحليل";
      toast.error(msg);
    } finally {
      setLoading(false);
    }
  }

  function reset() {
    setFile(null);
    setResult(null);
    if (inputRef.current) inputRef.current.value = "";
  }

  return (
    <div className="max-w-5xl mx-auto space-y-6">
      <header>
        <h1 className="text-2xl font-bold text-gray-900">تحليل صوتي</h1>
        <p className="text-sm text-gray-500 mt-1">
          ارفع ملفاً صوتياً وسيتم تحويله إلى نص وعرض إحصائيات تفصيلية عنه.
        </p>
      </header>

      <Card className="p-6">
        <label
          htmlFor="audio-input"
          onDragOver={(e) => {
            e.preventDefault();
            setDragActive(true);
          }}
          onDragLeave={() => setDragActive(false)}
          onDrop={onDrop}
          className={`block border-2 border-dashed rounded-xl p-8 text-center cursor-pointer transition ${
            dragActive
              ? "border-blue-500 bg-blue-50"
              : "border-gray-300 hover:border-gray-400 bg-gray-50"
          }`}
        >
          <input
            ref={inputRef}
            id="audio-input"
            type="file"
            accept="audio/*,.mp3,.wav,.m4a,.ogg,.opus,.flac,.webm,.aac"
            className="hidden"
            onChange={(e) => pickFile(e.target.files?.[0] || null)}
          />
          <div className="text-4xl mb-2">🎤</div>
          <p className="text-sm font-semibold text-gray-700">
            اضغط للاختيار أو اسحب الملف هنا
          </p>
          <p className="text-xs text-gray-500 mt-1">
            mp3 · wav · m4a · ogg · opus · حد أقصى ١٠٠ م.ب
          </p>
        </label>

        {file && (
          <div className="mt-6 space-y-4">
            <div className="flex items-center justify-between gap-3 bg-gray-50 rounded-lg p-3">
              <div className="min-w-0 flex-1">
                <p className="text-sm font-medium text-gray-900 truncate" dir="ltr">
                  {file.name}
                </p>
                <p className="text-xs text-gray-500 mt-0.5">{formatBytes(file.size)}</p>
              </div>
              <button
                onClick={reset}
                disabled={loading}
                className="text-sm text-red-600 hover:text-red-700 disabled:opacity-50"
                aria-label="إزالة الملف"
              >
                إزالة
              </button>
            </div>

            {audioUrl && (
              <audio controls src={audioUrl} className="w-full" dir="ltr">
                المتصفح لا يدعم تشغيل الصوت
              </audio>
            )}

            <Button onClick={analyze} disabled={loading} className="w-full">
              {loading ? (
                <span className="flex items-center justify-center gap-2">
                  <span className="inline-block h-4 w-4 animate-spin rounded-full border-2 border-white border-t-transparent" />
                  جاري التحليل...
                </span>
              ) : (
                "تحليل الصوت"
              )}
            </Button>
          </div>
        )}
      </Card>

      {result && <Results result={result} />}
    </div>
  );
}

function Results({ result }: { result: AnalyzeAudioResponse }) {
  const stats: { label: string; value: string; hint?: string }[] = [
    { label: "اللغة", value: result.language_name, hint: result.language },
    { label: "المدة", value: formatSeconds(result.duration_seconds) },
    { label: "عدد الكلمات", value: formatNumber(result.word_count) },
    { label: "كلمات فريدة", value: formatNumber(result.unique_word_count) },
    { label: "عدد الحروف", value: formatNumber(result.char_count) },
    { label: "حروف بدون مسافات", value: formatNumber(result.char_count_no_spaces) },
    { label: "عدد الجمل", value: formatNumber(result.sentence_count) },
    { label: "عدد الفقرات", value: formatNumber(result.paragraph_count) },
    { label: "عدد الأسطر", value: formatNumber(result.line_count) },
    { label: "عدد المقاطع الزمنية", value: formatNumber(result.segment_count) },
    { label: "متوسط طول الكلمة", value: formatNumber(result.avg_word_length) },
    {
      label: "سرعة الكلام (كلمة/دقيقة)",
      value: result.speaking_rate_wpm == null ? "—" : formatNumber(result.speaking_rate_wpm),
    },
  ];

  const punctEntries = Object.entries(result.punctuation || {}).filter(
    ([, c]) => typeof c === "number" && c > 0,
  );

  return (
    <div className="space-y-6">
      {/* Top summary */}
      <Card className="p-6">
        <div className="flex flex-wrap items-baseline gap-x-4 gap-y-2 mb-2">
          <h2 className="text-lg font-bold text-gray-900">نتيجة التحليل</h2>
          <span className="text-xs text-gray-500" dir="ltr">
            {result.provider}
            {result.model ? ` · ${result.model}` : ""}
          </span>
          <span className="text-xs text-gray-500">
            حجم الملف: {formatBytes(result.file.size_bytes)}
          </span>
        </div>
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
          {stats.map((s) => (
            <div key={s.label} className="bg-gray-50 rounded-lg p-3">
              <p className="text-xs text-gray-500 mb-1">{s.label}</p>
              <p className="text-lg font-bold text-gray-900">{s.value}</p>
              {s.hint && (
                <p className="text-xs text-gray-400 mt-0.5" dir="ltr">
                  {s.hint}
                </p>
              )}
            </div>
          ))}
        </div>
      </Card>

      {/* Transcript */}
      <Card className="p-6">
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-base font-semibold text-gray-900">النص المحوّل</h3>
          <button
            onClick={async () => {
              try {
                await navigator.clipboard.writeText(result.text);
                toast.success("تم النسخ");
              } catch {
                toast.error("تعذّر النسخ");
              }
            }}
            className="text-sm text-blue-600 hover:text-blue-700"
          >
            نسخ
          </button>
        </div>
        <div
          className="bg-gray-50 rounded-lg p-4 text-sm text-gray-800 leading-relaxed whitespace-pre-wrap max-h-96 overflow-auto"
          dir="auto"
        >
          {result.text || "(لا يوجد نص)"}
        </div>
      </Card>

      {/* Punctuation + Top words side by side */}
      <div className="grid md:grid-cols-2 gap-6">
        <Card className="p-6">
          <h3 className="text-base font-semibold text-gray-900 mb-3">علامات الترقيم</h3>
          {punctEntries.length === 0 ? (
            <p className="text-sm text-gray-500">لا توجد علامات ترقيم</p>
          ) : (
            <ul className="space-y-2">
              {punctEntries.map(([k, c]) => (
                <li
                  key={k}
                  className="flex items-center justify-between text-sm bg-gray-50 rounded px-3 py-2"
                >
                  <span className="text-gray-700">{PUNCT_LABEL[k] || k}</span>
                  <span className="font-semibold text-gray-900">{formatNumber(c)}</span>
                </li>
              ))}
            </ul>
          )}
        </Card>

        <Card className="p-6">
          <h3 className="text-base font-semibold text-gray-900 mb-3">
            الكلمات الأكثر تكراراً
          </h3>
          {result.top_words.length === 0 ? (
            <p className="text-sm text-gray-500">لا توجد بيانات</p>
          ) : (
            <ul className="space-y-2">
              {result.top_words.map((w) => (
                <li
                  key={w.word}
                  className="flex items-center justify-between text-sm bg-gray-50 rounded px-3 py-2"
                >
                  <span className="text-gray-700">{w.word}</span>
                  <span className="font-semibold text-gray-900">{formatNumber(w.count)}</span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>

      {/* Longest word */}
      {result.longest_word && (
        <Card className="p-6">
          <h3 className="text-base font-semibold text-gray-900 mb-2">أطول كلمة</h3>
          <p className="text-2xl font-bold text-blue-600">{result.longest_word}</p>
          <p className="text-xs text-gray-500 mt-1">
            {formatNumber(result.longest_word.length)} حرفاً
          </p>
        </Card>
      )}

      {/* Segments with timing */}
      {result.segments.length > 0 && (
        <Card className="p-6">
          <h3 className="text-base font-semibold text-gray-900 mb-3">
            المقاطع الزمنية ({formatNumber(result.segments.length)})
          </h3>
          <div className="max-h-96 overflow-auto rounded-lg border">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 sticky top-0">
                <tr>
                  <th className="text-start px-3 py-2 font-semibold text-gray-600">من</th>
                  <th className="text-start px-3 py-2 font-semibold text-gray-600">إلى</th>
                  <th className="text-start px-3 py-2 font-semibold text-gray-600">النص</th>
                </tr>
              </thead>
              <tbody>
                {result.segments.map((s) => (
                  <tr key={s.id} className="border-t">
                    <td className="px-3 py-2 text-gray-500 font-mono text-xs" dir="ltr">
                      {formatSeconds(s.start)}
                    </td>
                    <td className="px-3 py-2 text-gray-500 font-mono text-xs" dir="ltr">
                      {formatSeconds(s.end)}
                    </td>
                    <td className="px-3 py-2 text-gray-800" dir="auto">
                      {s.text}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      )}
    </div>
  );
}
