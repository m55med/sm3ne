@AGENTS.md

# Admin — Bisawtak-specific rules

> See [`../AGENTS.md`](../AGENTS.md) §4 for the full ruleset. The local `AGENTS.md` above adds the Next.js 16 caveat.

## Quick rules
- **ممنوع `window.confirm` و `alert`.** استخدم:
  - `<ConfirmDialog>` من `src/components/confirm-dialog.tsx`
  - `toast.success/error/info` من `src/components/toaster.tsx`
- **ممنوع `dangerouslySetInnerHTML`** — React escape بالـ default.
- **JWT validation:** استخدم `useAuth()` من `src/lib/auth.ts` — يفحص role + exp تلقائياً.
- **API calls:** كل HTTP عبر `api()` من `src/lib/api.ts` — يحمل التوكن ويعالج 401.
- **Labels:** استخدم `PLAN_LABEL`, `TICKET_STATUS_LABEL`, إلخ من `src/lib/labels.ts` — لا hardcode.
- **Numbers/Dates:** `formatNumber`, `formatDate`, `formatDateTime` من `src/lib/format.ts` (Intl, gregorian calendar).
- **RTL:** Tailwind 4 logical CSS — `border-s/e`, `me-/ms-`, `start-/end-`. ممنوع `border-l/r`, `mr-/ml-`, `left-/right-`.
- **Latin text داخل عربي:** لفّه في `<span dir="ltr">`.
- **Forms:** `htmlFor`/`id` على كل `<Label>` ↔ `<Input>` pair.
- **Destructive actions:** `<ConfirmDialog>` مع `destructive: true`.
- **Loading states:** `<SkeletonTable>` للجداول، spinner للأزرار.
- **Empty states:** `<EmptyState>` بدلاً من الفراغ.
- **Errors:** `<ErrorBoundary>` يلف كل صفحة. + try/catch + toast على كل mutation.

## Adding a new page
1. `src/app/(admin)/<route>/page.tsx`
2. أضف لـ sidebar في `src/app/(admin)/layout.tsx`.
3. types في `src/lib/types.ts`.
4. لو labels جديدة → `src/lib/labels.ts`.

## ممنوع
- `localStorage.setItem` لـ تفاصيل حساسة جديدة (التوكن نفسه حالياً هناك لكنه دين تقني — لا تضف عليه).
- `window.location.href = ...` — استخدم `router.replace()`.
- `console.error` في production paths — guard بـ `NODE_ENV`.

## CSP
محدّد في `next.config.ts`. لو أضفت host خارجي (CDN, analytics)، حدّث `connect-src` و `script-src`.
