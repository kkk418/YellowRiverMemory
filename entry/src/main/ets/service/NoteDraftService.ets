import { LocalRdbHelper } from '../database/LocalRdbHelper';
import { NoteTargetType } from '../common/constants/Enums';
import { EventBus, AppEvents } from '../common/utils/EventBus';

/** Drafts are local to this device and never enter the distributed outbox. */
export interface NoteDraft {
  id: string;
  noteId: string | null;
  title: string;
  content: string;
  targetType: NoteTargetType;
  targetId: string | null;
  tags: string;
  baseUpdatedAt: number;
  baseDeviceId: string;
  savedAt: number;
}

export class NoteDraftService {
  static async get(id: string): Promise<NoteDraft | null> {
    const rows = await LocalRdbHelper.query<NoteDraft>(
      'SELECT * FROM note_draft WHERE id=? LIMIT 1', [id]);
    return rows[0] ?? null;
  }

  static async list(): Promise<NoteDraft[]> {
    return LocalRdbHelper.query<NoteDraft>('SELECT * FROM note_draft ORDER BY savedAt DESC', []);
  }

  static async save(draft: NoteDraft): Promise<void> {
    await LocalRdbHelper.execute(
      `INSERT OR REPLACE INTO note_draft
       (id, noteId, title, content, targetType, targetId, tags, baseUpdatedAt, baseDeviceId, savedAt)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [draft.id, draft.noteId, draft.title, draft.content, draft.targetType, draft.targetId,
        draft.tags, draft.baseUpdatedAt, draft.baseDeviceId, draft.savedAt]);
    EventBus.getInstance().emit(AppEvents.NOTE_DRAFT_CHANGED, { id: draft.id });
  }

  static async delete(id: string): Promise<void> {
    await LocalRdbHelper.execute('DELETE FROM note_draft WHERE id=?', [id]);
    EventBus.getInstance().emit(AppEvents.NOTE_DRAFT_CHANGED, { id });
  }
}
