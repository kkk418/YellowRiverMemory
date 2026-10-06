/** Connects Navigation's system-back callback with the active note editor. */
export class NoteLeaveGuard {
  private static handler: (() => boolean) | null = null;

  static register(handler: () => boolean): void { NoteLeaveGuard.handler = handler; }
  static unregister(handler: () => boolean): void {
    if (NoteLeaveGuard.handler === handler) NoteLeaveGuard.handler = null;
  }
  static onBackPressed(): boolean {
    return NoteLeaveGuard.handler ? NoteLeaveGuard.handler() : false;
  }
}
