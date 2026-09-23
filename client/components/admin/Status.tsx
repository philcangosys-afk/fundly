interface StatusProps {
  state: 'loading' | 'error' | 'empty'
  message?: string
  onRetry?: () => void
}

export default function Status({ state, message, onRetry }: StatusProps) {
  if (state === 'loading') {
    return (
      <div className="flex items-center justify-center gap-3 py-12 text-[12.5px] font-bold text-ink-muted">
        <span className="h-4 w-4 animate-spin rounded-full border-2 border-hairline border-t-brand" />
        جارٍ التحميل…
      </div>
    )
  }

  if (state === 'error') {
    return (
      <div className="rounded-xl border border-[#C4392E]/25 bg-[#FBE7E4] px-4 py-5 text-center">
        <p className="text-[12.5px] font-extrabold text-[#C4392E]">{message ?? 'حدث خطأ'}</p>
        {onRetry && (
          <button
            type="button"
            onClick={onRetry}
            className="mt-3 rounded-xl bg-white px-4 py-2 text-[11.5px] font-extrabold text-[#C4392E]"
          >
            إعادة المحاولة
          </button>
        )}
      </div>
    )
  }

  return (
    <p className="py-12 text-center text-[12.5px] font-bold text-ink-muted">
      {message ?? 'لا توجد بيانات بعد'}
    </p>
  )
}
