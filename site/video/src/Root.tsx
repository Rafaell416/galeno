import React from 'react';
import { Composition } from 'remotion';
import './fonts';
import { Hero, heroDuration } from './Hero';
import { WhatsApp, whatsappDuration } from './WhatsApp';
import { FPS, H, W } from './theme';

// La duración total resta las superposiciones de 8 cuadros entre escenas: no cuentan en el tiempo final.
const heroFrames = heroDuration;

export const Root: React.FC = () => (
  <>
    <Composition id="Hero-es" component={Hero} durationInFrames={heroFrames} fps={FPS} width={W} height={H} defaultProps={{ lang: 'es' as const }} />
    <Composition id="Hero-en" component={Hero} durationInFrames={heroFrames} fps={FPS} width={W} height={H} defaultProps={{ lang: 'en' as const }} />
    <Composition id="WhatsApp-es" component={WhatsApp} durationInFrames={whatsappDuration} fps={FPS} width={W} height={H} defaultProps={{ lang: 'es' as const }} />
    <Composition id="WhatsApp-en" component={WhatsApp} durationInFrames={whatsappDuration} fps={FPS} width={W} height={H} defaultProps={{ lang: 'en' as const }} />
  </>
);
