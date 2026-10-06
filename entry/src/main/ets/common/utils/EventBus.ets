/**
 * 轻量级事件总线（发布-订阅），模块间解耦通信
 */
import { SyncStatus } from '../constants/Enums';
import { Logger } from './Logger';

export interface EventPayload {
  id?: string;
  targetType?: string;
  targetId?: string;
  favorited?: boolean;
  tagsUpdated?: boolean;
  deleted?: boolean;
  remote?: boolean;
  conflictResolved?: boolean;
  source?: string;
}

export interface SyncStatusPayload {
  status: SyncStatus;
}

export type EventData = EventPayload | SyncStatusPayload | null;
export type EventHandler = (data?: EventData) => void;

interface EventEntry {
  handler: EventHandler;
  once: boolean;
}

export class EventBus {
  private static instance: EventBus;
  private channels: Map<string, EventEntry[]> = new Map();

  static getInstance(): EventBus {
    if (!EventBus.instance) {
      EventBus.instance = new EventBus();
    }
    return EventBus.instance;
  }

  on(event: string, handler: EventHandler): void {
    this.addEntry(event, { handler, once: false });
  }

  once(event: string, handler: EventHandler): void {
    this.addEntry(event, { handler, once: true });
  }

  off(event: string, handler?: EventHandler): void {
    if (!this.channels.has(event)) return;
    if (!handler) {
      this.channels.delete(event);
      return;
    }
    const list = this.channels.get(event)!;
    const idx = list.findIndex(e => e.handler === handler);
    if (idx >= 0) list.splice(idx, 1);
  }

  emit(event: string, data?: EventData): void {
    if (!this.channels.has(event)) return;
    const list = this.channels.get(event)!;
    const snapshot = [...list];
    for (const entry of snapshot) {
      try {
        entry.handler(data);
      } catch (e) {
        Logger.error('EventBus', `listener failed for ${event}: ${e}`);
      }
      if (entry.once) {
        const idx = list.indexOf(entry);
        if (idx >= 0) list.splice(idx, 1);
      }
    }
  }

  clear(): void {
    this.channels.clear();
  }

  private addEntry(event: string, entry: EventEntry): void {
    if (!this.channels.has(event)) {
      this.channels.set(event, []);
    }
    this.channels.get(event)!.push(entry);
  }
}

/**
 * 全局事件名常量
 */
export class AppEvents {
  static FAVORITE_CHANGED = 'favorite_changed';
  static NOTE_CHANGED = 'note_changed';
  static NOTE_DRAFT_CHANGED = 'note_draft_changed';
  static HISTORY_CHANGED = 'history_changed';
  static TOPIC_CHANGED = 'topic_changed';
  static SYNC_STATUS_CHANGED = 'sync_status_changed';
  static SYNC_CONFLICT_DETECTED = 'sync_conflict';
  static THEME_CHANGED = 'theme_changed';
  static DATA_INIT_COMPLETED = 'data_init_completed';
  static APP_FOREGROUND = 'app_foreground';
  static APP_BACKGROUND = 'app_background';
}
