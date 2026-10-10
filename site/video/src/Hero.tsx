import React from 'react';
import { AbsoluteFill, Img, Sequence, interpolate, staticFile, useCurrentFrame } from 'remotion';
import { c, font, H, W } from './theme';
import { Cursor, Kicker, Ripple, Title, Wordmark, ease, prog } from './lib';
import { hero, type Lang } from './copy';

// Las capturas son 1600×1304 (la ventana real de la app a 2x). Todo lo que se dibuja encima usa esas coordenadas.
const IMG_W = 1600;
const IMG_H = 1304;
const S = 0.69; // escala de la ventana en el lienzo de 1920×1080
const WIN_W = IMG_W * S;
const WIN_H = IMG_H * S;
const WIN_X = W - WIN_W - 96;
const WIN_Y = (H - WIN_H) / 2;
const OVERLAP = 8;

type Still = { name: string; at: number };
type CursorKey = { at: number; x: number; y: number; click?: boolean };
type Zoom = { at: number; dur: number; scale: number; x: number; y: number };
type Mark = { at: number; x: number; y: number; w: number; h: number };
type Scene = { stills: Still[]; dur: number; cursor?: CursorKey[]; zoom?: Zoom; mark?: Mark };

// Posiciones en píxeles de la captura: coordenadas de la ventana (800×652) por 2.
const SEGUIR = { x: 1412, y: 1232 };
const scenes: Scene[] = [
  {
    // 1 · rol
    stills: [{ name: '01-rol', at: 0 }],
    dur: 66,
    cursor: [
      { at: 0, x: 1180, y: 940 },
      { at: 26, x: 320, y: 620, click: true },
      { at: 54, x: SEGUIR.x, y: SEGUIR.y, click: true },
    ],
  },
  {
    // 2 · nombre
    stills: [{ name: '03-nombre', at: 0 }],
    dur: 54,
    mark: { at: 8, x: 84, y: 436, w: 870, h: 96 },
  },
  {
    // 3 · herramientas
    stills: [
      { name: '04-herramientas-0', at: 0 },
      { name: '04-herramientas-1', at: 24 },
      { name: '04-herramientas-2', at: 40 },
      { name: '04-herramientas-3', at: 56 },
    ],
    dur: 92,
    cursor: [
      { at: 0, x: 1100, y: 1000 },
      { at: 20, x: 326, y: 588, click: true },
      { at: 36, x: 802, y: 588, click: true },
      { at: 52, x: 802, y: 732, click: true },
      { at: 78, x: 1382, y: 1232, click: true },
    ],
  },
  {
    // 4 · conectar
    stills: [
      { name: '05-jira-antes', at: 0 },
      { name: '07-jira-ok', at: 40 },
    ],
    dur: 78,
    cursor: [
      { at: 0, x: 1300, y: 1000 },
      { at: 22, x: 1372, y: 1228, click: true },
    ],
  },
  {
    // 5 · WhatsApp
    stills: [{ name: '08-whatsapp', at: 0 }],
    dur: 78,
    mark: { at: 14, x: 100, y: 800, w: 680, h: 100 },
  },
  {
    // 6 · skills
    stills: [
      { name: '10-skills-documentos', at: 0 },
      { name: '11-skills-informes', at: 52 },
    ],
    dur: 104,
  },
  {
    // 7 · reglas
    stills: [{ name: '12-reglas', at: 0 }],
    dur: 90,
    mark: { at: 14, x: 340, y: 380, w: 1170, h: 104 },
  },
  {
    // 8 · listo
    stills: [{ name: '15-listo', at: 0 }],
    dur: 66,
  },
];
const END_DUR = 60;

export const heroDuration = scenes.reduce((a, s) => a + s.dur, 0) + END_DUR; // sin contar las superposiciones

const cursorAt = (keys: CursorKey[], f: number) => {
  if (f <= keys[0].at) return { x: keys[0].x, y: keys[0].y };
  for (let i = 1; i < keys.length; i++) {
    if (f <= keys[i].at) {
      const p = interpolate(f, [keys[i - 1].at, keys[i].at], [0, 1], { easing: ease, extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
      return { x: keys[i - 1].x + (keys[i].x - keys[i - 1].x) * p, y: keys[i - 1].y + (keys[i].y - keys[i - 1].y) * p };
    }
  }
  const last = keys[keys.length - 1];
  return { x: last.x, y: last.y };
};

const SceneView: React.FC<{ scene: Scene; lang: Lang; index: number; first: boolean }> = ({ scene, lang, index, first }) => {
  const f = useCurrentFrame();
  const step = hero[lang].steps[index];
  const fade = first ? 1 : prog(f, 0, OVERLAP);
  // Un avance muy suave en todas las escenas; nada recorta los bordes de la captura.
  const zoom = scene.zoom ?? { at: 0, dur: scene.dur + OVERLAP, scale: 1.025, x: IMG_W * 0.15, y: IMG_H * 0.1 };
  const z = 1 + (zoom.scale - 1) * interpolate(f, [zoom.at, zoom.at + zoom.dur], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
  const origin = `${zoom.x}px ${zoom.y}px`;
  const markIn = scene.mark ? prog(f, scene.mark.at, 22) : 0;
  const cur = scene.cursor ? cursorAt(scene.cursor, f) : null;
  const titleIn = prog(f, 2, 16);
  const subIn = prog(f, 8, 16);

  return (
    <AbsoluteFill style={{ opacity: fade }}>
      {/* La ventana: marco fijo; lo que se mueve (zoom) va dentro */}
      <div
        style={{
          position: 'absolute',
          left: WIN_X,
          top: WIN_Y,
          width: WIN_W,
          height: WIN_H,
          borderRadius: 24,
          overflow: 'hidden',
          border: `1.5px solid ${c.ink300}`,
          background: c.parchment100,
        }}
      >
        <div style={{ width: IMG_W, height: IMG_H, transform: `scale(${S})`, transformOrigin: '0 0', position: 'relative' }}>
          <div style={{ position: 'absolute', inset: 0, transform: `scale(${z})`, transformOrigin: origin }}>
            {scene.stills.map((s, i) => (
              <Img
                key={s.name}
                src={staticFile(`shots/${lang}/${s.name}.jpg`)}
                style={{ position: 'absolute', inset: 0, width: IMG_W, height: IMG_H, opacity: i === 0 ? 1 : prog(f, s.at, 8) }}
              />
            ))}
            {scene.mark && (
              <div
                style={{
                  position: 'absolute',
                  left: scene.mark.x,
                  top: scene.mark.y,
                  width: scene.mark.w,
                  height: scene.mark.h,
                  border: `5px solid ${c.seal700}`,
                  borderRadius: 14,
                  boxSizing: 'border-box',
                  opacity: 0.85 * markIn,
                  clipPath: `inset(0 ${(1 - markIn) * 100}% 0 0)`,
                }}
              />
            )}
            {scene.cursor?.filter((k) => k.click).map((k) => (
              <Ripple key={k.at} x={k.x} y={k.y} t={(f - k.at) / 20} size={150} />
            ))}
            {cur && (
              <div style={{ opacity: prog(f, 0, 8) }}>
                <Cursor x={cur.x} y={cur.y} size={64} />
              </div>
            )}
          </div>
        </div>
      </div>

      {/* El texto, a la izquierda */}
      <div style={{ position: 'absolute', left: 96, top: 320, width: WIN_X - 96 - 48 }}>
        <div style={{ opacity: titleIn, transform: `translateY(${(1 - titleIn) * 24}px)` }}>
          <Kicker text={step.k} />
          <div style={{ height: 18 }} />
          <Title text={step.t} size={78} />
        </div>
        <div style={{ height: 26 }} />
        <div
          style={{
            fontFamily: font.text,
            fontSize: 34,
            lineHeight: 1.35,
            color: c.ink700,
            opacity: subIn,
            transform: `translateY(${(1 - subIn) * 18}px)`,
          }}
        >
          {step.s}
        </div>
      </div>
    </AbsoluteFill>
  );
};

const EndCard: React.FC<{ lang: Lang }> = ({ lang }) => {
  const f = useCurrentFrame();
  const a = prog(f, 0, OVERLAP);
  const b = prog(f, 6, 18);
  const t = hero[lang];
  return (
    <AbsoluteFill style={{ opacity: a, alignItems: 'center', justifyContent: 'center', background: c.parchment50 }}>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 36, opacity: b, transform: `translateY(${(1 - b) * 20}px)` }}>
        <div style={{ width: 240, height: 240, borderRadius: '50%', border: `2px solid ${c.ink500}`, padding: 8, boxSizing: 'border-box' }}>
          <div style={{ width: '100%', height: '100%', borderRadius: '50%', border: `3px solid ${c.ink900}`, overflow: 'hidden' }}>
            <Img src={staticFile('retrato.jpg')} style={{ width: '100%', height: '100%', objectFit: 'cover', objectPosition: '52% 42%' }} />
          </div>
        </div>
        <Wordmark size={132} />
        <div style={{ fontFamily: font.text, fontSize: 46, color: c.ink700 }}>{t.end2}</div>
        <Kicker text={t.endTag} size={26} />
      </div>
    </AbsoluteFill>
  );
};

export const Hero: React.FC<{ lang: Lang }> = ({ lang }) => {
  const frame = useCurrentFrame();
  let from = 0;
  const parts = scenes.map((scene, i) => {
    const start = from;
    from += scene.dur;
    return { scene, i, start };
  });
  const total = heroDuration;
  const progress = interpolate(frame, [0, total], [0, 1], { extrapolateRight: 'clamp' });

  return (
    <AbsoluteFill style={{ background: c.parchment50 }}>
      {parts.map(({ scene, i, start }) => (
        <Sequence key={i} from={start} durationInFrames={scene.dur + OVERLAP}>
          <SceneView scene={scene} lang={lang} index={i} first={i === 0} />
        </Sequence>
      ))}
      <Sequence from={from} durationInFrames={END_DUR + 4}>
        <EndCard lang={lang} />
      </Sequence>

      {/* Marca arriba y regla de avance abajo, siempre a la vista (menos en la tarjeta final) */}
      <div style={{ opacity: interpolate(frame, [from - 4, from + 4], [1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' }) }}>
        <div style={{ position: 'absolute', left: 96, top: 84 }}>
          <Wordmark size={34} />
        </div>
        <div style={{ position: 'absolute', left: 96, top: H - 112, width: 420, height: 3, background: c.ink300 }}>
          <div style={{ width: `${progress * 100}%`, height: 3, background: c.ink900 }} />
        </div>
      </div>
    </AbsoluteFill>
  );
};
