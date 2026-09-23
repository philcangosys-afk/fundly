import { useState } from 'react'
import { monthLabel } from '@/lib/format'

interface Point {
  key: string
  label: string
  value: number
}

interface TrendChartProps {
  data: Point[]
  /** اسم ما يُقاس — يظهر في التلميحة. سلسلة واحدة فلا حاجة لمفتاح ألوان. */
  measure: string
  height?: number
}

const PADDING = { top: 16, right: 14, bottom: 26, left: 34 }

/**
 * خط زمني بسلسلة واحدة: شبكة خافتة، خط 2px، نقاط 8px، تلميحة عند المرور،
 * وقيمة آخر نقطة مكتوبة مباشرة — فلا يحتاج القارئ إلى تخمين.
 */
export default function TrendChart({ data, measure, height = 200 }: TrendChartProps) {
  const [hover, setHover] = useState<number | null>(null)
  const width = 640
  const innerWidth = width - PADDING.left - PADDING.right
  const innerHeight = height - PADDING.top - PADDING.bottom

  const max = Math.max(1, ...data.map((point) => point.value))
  const stepX = data.length > 1 ? innerWidth / (data.length - 1) : 0

  const x = (index: number) => PADDING.left + index * stepX
  const y = (value: number) => PADDING.top + innerHeight - (value / max) * innerHeight

  const line = data.map((point, index) => `${index === 0 ? 'M' : 'L'} ${x(index)} ${y(point.value)}`).join(' ')
  const area = `${line} L ${x(data.length - 1)} ${PADDING.top + innerHeight} L ${x(0)} ${
    PADDING.top + innerHeight
  } Z`

  const ticks = [0, 0.5, 1].map((ratio) => Math.round(max * ratio))
  const last = data[data.length - 1]
  const active = hover !== null ? data[hover] : null

  return (
    <figure className="m-0">
      <div className="relative">
        <svg
          viewBox={`0 0 ${width} ${height}`}
          className="w-full"
          role="img"
          aria-label={`${measure} على مدى ${data.length} شهرًا`}
          onMouseLeave={() => setHover(null)}
        >
          {ticks.map((tick) => (
            <g key={tick}>
              <line
                x1={PADDING.left}
                x2={width - PADDING.right}
                y1={y(tick)}
                y2={y(tick)}
                stroke="var(--viz-grid)"
                strokeWidth={1}
              />
              <text
                x={PADDING.left - 8}
                y={y(tick) + 4}
                textAnchor="end"
                className="fill-ink-muted text-[10px] font-bold"
              >
                {tick}
              </text>
            </g>
          ))}

          <path d={area} fill="var(--series-1)" opacity={0.1} />
          <path d={line} fill="none" stroke="var(--series-1)" strokeWidth={2} strokeLinejoin="round" />

          {data.map((point, index) => (
            <g key={point.key}>
              {(index === data.length - 1 || hover === index) && (
                <circle
                  cx={x(index)}
                  cy={y(point.value)}
                  r={4.5}
                  fill="var(--series-1)"
                  stroke="var(--viz-surface)"
                  strokeWidth={2}
                />
              )}
              <rect
                x={x(index) - stepX / 2}
                y={PADDING.top}
                width={Math.max(stepX, 18)}
                height={innerHeight}
                fill="transparent"
                onMouseEnter={() => setHover(index)}
              />
            </g>
          ))}

          {data.map((point, index) =>
            index % 2 === 0 || data.length <= 8 ? (
              <text
                key={`label-${point.key}`}
                x={x(index)}
                y={height - 8}
                textAnchor="middle"
                className="fill-ink-muted text-[9.5px] font-bold"
              >
                {monthLabel(point.label)}
              </text>
            ) : null,
          )}

          {last && (
            <text
              x={x(data.length - 1)}
              y={y(last.value) - 10}
              textAnchor="end"
              className="fill-ink-title text-[11px] font-black"
            >
              {last.value}
            </text>
          )}
        </svg>

        {active && (
          <div
            className="pointer-events-none absolute -translate-y-full rounded-xl border border-hairline bg-white px-3 py-2 shadow-[0_2px_10px_rgba(15,31,28,.08)]"
            style={{
              insetInlineStart: `${((x(hover ?? 0) / width) * 100).toFixed(2)}%`,
              top: `${((y(active.value) / height) * 100).toFixed(2)}%`,
              transform: 'translate(-50%, -12px)',
            }}
          >
            <p className="whitespace-nowrap text-[10.5px] font-bold text-ink-muted">
              {monthLabel(active.label)}
            </p>
            <p className="whitespace-nowrap text-[12px] font-black text-ink-title">
              {active.value} {measure}
            </p>
          </div>
        )}
      </div>
    </figure>
  )
}
