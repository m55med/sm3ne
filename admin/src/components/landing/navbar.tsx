import Link from "next/link";

export function Navbar() {
  return (
    <nav className="sticky top-0 z-50 bg-white/80 backdrop-blur-md border-b">
      <div className="max-w-6xl mx-auto px-6 h-16 flex items-center justify-between">
        <Link href="/" className="text-2xl font-bold text-blue-600">
          بصوتك
        </Link>
        <div className="flex items-center gap-4">
          <Link href="#features" className="text-sm text-gray-600 hover:text-gray-900 hidden sm:block">المميزات</Link>
          <Link href="#plans" className="text-sm text-gray-600 hover:text-gray-900 hidden sm:block">الباقات</Link>
          <Link href="#faq" className="text-sm text-gray-600 hover:text-gray-900 hidden sm:block">الأسئلة</Link>
          <Link href="/login" className="text-sm bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700 transition">
            لوحة التحكم
          </Link>
        </div>
      </div>
    </nav>
  );
}
