import type {Photo, PhotoBatch} from './bridge';

export interface CaptureDraft {
  photo?: Photo;
  photos: Photo[];
  group?: PhotoBatch;
  batchMode: boolean;
  reviewing: boolean;
  reviewIndex: number;
}
export interface DraftShelf {active: CaptureDraft; saved: CaptureDraft[]}
export const emptyDraft = (batchMode = false): CaptureDraft => ({photos: [], batchMode, reviewing: false, reviewIndex: 0});
export const hasMedia = (draft: CaptureDraft): boolean => !!draft.photo || draft.photos.length > 0;
export const draftFiles = (draft: CaptureDraft): Photo[] => draft.photo ? [draft.photo] : draft.photos;

export function receiveDraft(shelf: DraftShelf, incoming: Photo | PhotoBatch): DraftShelf {
  const saved = hasMedia(shelf.active) ? [...shelf.saved, shelf.active] : shelf.saved;
  const active = 'images' in incoming
    ? {...emptyDraft(true), photos: incoming.images, group: incoming, reviewing: true}
    : {...emptyDraft(shelf.active.batchMode), photo: incoming};
  return {active, saved};
}

export function finishDraft(shelf: DraftShelf): DraftShelf {
  const [first, ...saved] = shelf.saved;
  return {active: first ?? emptyDraft(shelf.active.batchMode), saved};
}

export function selectDraft(shelf: DraftShelf, index: number): DraftShelf {
  const selected = shelf.saved[index];
  if (!selected) return shelf;
  const saved = shelf.saved.filter((_, item) => item !== index);
  if (hasMedia(shelf.active)) saved.push(shelf.active);
  return {active: {...selected, reviewing: selected.photos.length > 0}, saved};
}
