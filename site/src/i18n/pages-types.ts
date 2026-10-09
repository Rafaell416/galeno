// Las páginas largas (documentación, privacidad, términos) son datos: título, secciones y bloques.
// Marcado en línea permitido: `código`, **negrita** y [texto](dirección). El resto se escapa.
export type Block =
  | { p: string }
  | { ul: string[] }
  | { ol: string[] }
  | { code: string }
  | { note: string };

export interface Section { id: string; h: string; blocks: Block[] }

export interface LongPage {
  title: string;
  metaDescription: string;
  kicker: string;
  intro?: string;
  updated?: string;
  sections: Section[];
}
