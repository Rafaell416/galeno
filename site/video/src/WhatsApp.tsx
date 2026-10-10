import React from 'react';
import { AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame } from 'remotion';
import { c, font } from './theme';
import { Cursor, Kicker, Ripple, Wordmark, ease, prog } from './lib';
import { whatsapp, type Lang } from './copy';

export const whatsappDuration = 450; // 15 s a 30 fps

const card: React.CSSProperties = {
  background: c.parchment100,
  border: `2px solid ${c.parchment300}`,
  borderRadius: 18,
  padding: '22px 28px',
  boxSizing: 'border-box',
};
const label: React.CSSProperties = {
  fontFamily: font.display,
  fontWeight: 500,
  fontSize: 18,
  letterSpacing: '0.14em',
  textTransform: 'uppercase',
  color: c.ink700,
  marginBottom: 8,
};

const Arrow: React.FC<{ p: number }> = ({ p }) => (
  <svg width="110" height="40" viewBox="0 0 110 40" fill="none" stroke={c.ink500} strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
    <path d="M2 20H104" strokeDasharray="104" strokeDashoffset={104 * (1 - p)} />
    <path d="M90 6l16 14-16 14" opacity={p > 0.9 ? 1 : 0} />
  </svg>
);

export const WhatsApp: React.FC<{ lang: Lang }> = ({ lang }) => {
  const f = useCurrentFrame();
  const t = whatsapp[lang];

  // La frase de arriba cambia con la historia.
  const phase = f < 120 ? 0 : f < 270 ? 1 : 2;
  const line = [t.h1, t.h2, t.h3][phase];
  const lineIn = prog(f, [0, 120, 270][phase], 16);

  // Posiciones (en el lienzo de 1920×1080)
  const approveX = 1352;
  const approveY = 856;
  const cursorStart = { x: 1640, y: 990 };
  const cx = interpolate(f, [236, 266], [cursorStart.x, approveX], { easing: ease, extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
  const cy = interpolate(f, [236, 266], [cursorStart.y, approveY], { easing: ease, extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
  const clickT = (f - 270) / 20;
  const approved = f >= 276;
  const sentIn = prog(f, 278, 14);

  const endIn = prog(f, 360, 22);

  return (
    <AbsoluteFill style={{ background: c.parchment50 }}>
      <div style={{ position: 'absolute', left: 96, top: 72, opacity: 1 - endIn }}>
        <Wordmark size={34} />
      </div>

      {/* La frase de cada momento */}
      <div
        style={{
          position: 'absolute',
          left: 96,
          top: 150,
          fontFamily: font.text,
          fontWeight: 600,
          fontSize: 76,
          color: c.ink900,
          letterSpacing: -0.5,
          opacity: lineIn * (1 - endIn),
          transform: `translateY(${(1 - lineIn) * 22}px)`,
        }}
      >
        {line.slice(0, -1)}
        <span style={{ color: c.seal700 }}>.</span>
      </div>

      {/* Columna izquierda: los chats */}
      <div style={{ position: 'absolute', left: 96, top: 330, width: 560, opacity: 1 - endIn }}>
        <div style={{ ...label, marginBottom: 16, opacity: prog(f, 4, 14) }}>{t.chatsTitle}</div>
        <div style={{ display: 'grid', gap: 18 }}>
          {t.chats.map((chat, i) => {
            const p = prog(f, 10 + i * 14, 18);
            return (
              <div key={i} style={{ ...card, opacity: p, transform: `translateY(${(1 - p) * 30}px)` }}>
                <div style={{ ...label, fontSize: 16, marginBottom: 6 }}>{chat.who}</div>
                <div style={{ fontFamily: font.text, fontStyle: 'italic', fontSize: 30, lineHeight: 1.3, color: c.ink900 }}>{chat.msg}</div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Centro: flechas y Galeno */}
      <div style={{ position: 'absolute', left: 690, top: 520, opacity: 1 - endIn }}>
        <Arrow p={prog(f, 66, 20)} />
      </div>
      <div
        style={{
          position: 'absolute',
          left: 806,
          top: 440,
          width: 300,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          gap: 18,
          opacity: prog(f, 70, 18) * (1 - endIn),
          transform: `scale(${0.9 + 0.1 * prog(f, 70, 22)})`,
        }}
      >
        <div style={{ width: 210, height: 210, borderRadius: '50%', border: `2px solid ${c.ink500}`, padding: 7, boxSizing: 'border-box' }}>
          <div style={{ width: '100%', height: '100%', borderRadius: '50%', border: `3px solid ${c.ink900}`, overflow: 'hidden' }}>
            <Img src={staticFile('retrato.jpg')} style={{ width: '100%', height: '100%', objectFit: 'cover', objectPosition: '52% 42%' }} />
          </div>
        </div>
        <Kicker text={t.reads} size={24} />
      </div>
      <div style={{ position: 'absolute', left: 1116, top: 520, opacity: 1 - endIn }}>
        <Arrow p={prog(f, 90, 20)} />
      </div>

      {/* Columna derecha: lo que devuelve */}
      <div style={{ position: 'absolute', left: 1240, top: 330, width: 584, opacity: 1 - endIn }}>
        <div style={{ ...label, marginBottom: 16, opacity: prog(f, 100, 14) }}>{t.outTitle}</div>
        <div style={{ display: 'grid', gap: 18 }}>
          {[t.waiting, t.promised].map((o, i) => {
            const p = prog(f, 108 + i * 28, 18);
            return (
              <div key={i} style={{ ...card, opacity: p, transform: `translateY(${(1 - p) * 30}px)` }}>
                <div style={{ ...label, fontSize: 16, color: i === 0 ? c.seal700 : c.ink700, marginBottom: 6 }}>{o.l}</div>
                <div style={{ fontFamily: font.text, fontSize: 30, lineHeight: 1.3, color: c.ink900 }}>{o.t}</div>
              </div>
            );
          })}
          {(() => {
            const p = prog(f, 168, 20);
            return (
              <div
                style={{
                  ...card,
                  border: `2.5px solid ${approved ? c.moss700 : c.ink900}`,
                  opacity: p,
                  transform: `translateY(${(1 - p) * 30}px)`,
                  background: approved ? '#E6EEE8' : c.parchment100,
                }}
              >
                <div style={{ ...label, fontSize: 16, marginBottom: 6 }}>{t.proposal.l}</div>
                <div style={{ fontFamily: font.text, fontStyle: 'italic', fontSize: 30, lineHeight: 1.3, color: c.ink900 }}>{t.proposal.t}</div>
                <div style={{ height: 22 }} />
                {!approved ? (
                  <div style={{ display: 'flex', gap: 14 }}>
                    <span style={{ fontFamily: font.display, fontWeight: 500, fontSize: 20, letterSpacing: '0.1em', textTransform: 'uppercase', background: c.ink900, color: c.parchment50, borderRadius: 12, padding: '14px 26px' }}>{t.approve}</span>
                    <span style={{ fontFamily: font.display, fontWeight: 500, fontSize: 20, letterSpacing: '0.1em', textTransform: 'uppercase', border: `2.5px solid ${c.ink900}`, color: c.ink900, borderRadius: 12, padding: '12px 24px' }}>{t.edit}</span>
                  </div>
                ) : (
                  <div style={{ fontFamily: font.display, fontWeight: 500, fontSize: 20, letterSpacing: '0.1em', textTransform: 'uppercase', color: c.moss700, opacity: sentIn }}>
                    ✓ {t.sent}
                  </div>
                )}
              </div>
            );
          })()}
        </div>
      </div>

      {/* El cursor aprueba */}
      {f >= 236 && f < 330 && (
        <div style={{ opacity: prog(f, 236, 8) * (1 - prog(f, 300, 20)) }}>
          <Ripple x={approveX} y={approveY} t={clickT} size={130} />
          <Cursor x={cx} y={cy} size={64} />
        </div>
      )}

      {/* Cierre */}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          gap: 30,
          opacity: endIn,
          transform: `translateY(${(1 - endIn) * 20}px)`,
        }}
      >
        <Wordmark size={120} />
        <div style={{ fontFamily: font.text, fontWeight: 600, fontSize: 64, color: c.ink900 }}>
          {t.endLine.slice(0, -1)}
          <span style={{ color: c.seal700 }}>.</span>
        </div>
      </div>

      <div style={{ position: 'absolute', left: 96, bottom: 56, fontFamily: font.text, fontSize: 24, fontStyle: 'italic', color: c.ink500 }}>{t.note}</div>
    </AbsoluteFill>
  );
};
