import React from 'react';
import { Easing, interpolate } from 'remotion';
import { c, font } from './theme';

export const ease = Easing.bezier(0.22, 1, 0.36, 1);

/** 0→1 entre `start` y `start + dur`, con curva suave. */
export const prog = (frame: number, start: number, dur: number) =>
  interpolate(frame, [start, start + dur], [0, 1], { easing: ease, extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });

/** El título termina en punto lacre, como en la app («Reglas.»). */
export const Title: React.FC<{ text: string; size?: number; color?: string }> = ({ text, size = 72, color = c.ink900 }) => {
  const dot = text.endsWith('.');
  return (
    <div style={{ fontFamily: font.text, fontWeight: 600, fontSize: size, lineHeight: 1.08, color, letterSpacing: -0.5 }}>
      {dot ? text.slice(0, -1) : text}
      {dot && <span style={{ color: c.seal700 }}>.</span>}
    </div>
  );
};

export const Kicker: React.FC<{ text: string; color?: string; size?: number }> = ({ text, color = c.ink700, size = 22 }) => (
  <div style={{ fontFamily: font.display, fontWeight: 500, fontSize: size, letterSpacing: '0.14em', textTransform: 'uppercase', color }}>{text}</div>
);

export const Wordmark: React.FC<{ size: number }> = ({ size }) => (
  <span style={{ fontFamily: font.display, fontWeight: 700, fontSize: size, letterSpacing: '0.08em', color: c.ink900, lineHeight: 1 }}>
    GALENO<span style={{ color: c.seal700 }}>.</span>
  </span>
);

/** El puntero de macOS. `x`, `y` es la punta. */
export const Cursor: React.FC<{ x: number; y: number; size?: number }> = ({ x, y, size = 40 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" style={{ position: 'absolute', left: x - 2, top: y - 2, overflow: 'visible' }}>
    <path d="M3 2 L3 19 L7.4 15 L10.2 21.4 L12.9 20.2 L10.2 14 L16.3 14 Z" fill="#fff" stroke="#111" strokeWidth="1.4" strokeLinejoin="round" />
  </svg>
);

/** El círculo que se abre al hacer clic. */
export const Ripple: React.FC<{ x: number; y: number; t: number; size?: number }> = ({ x, y, t, size = 120 }) => {
  if (t < 0 || t > 1) return null;
  const r = size * t;
  return (
    <div
      style={{
        position: 'absolute',
        left: x - r / 2,
        top: y - r / 2,
        width: r,
        height: r,
        borderRadius: '50%',
        border: `4px solid ${c.seal700}`,
        opacity: 0.55 * (1 - t),
      }}
    />
  );
};
