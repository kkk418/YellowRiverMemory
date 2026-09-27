/**
 * 日期/时间工具
 */
export class DateUtil {
  static formatDate(timestamp: number): string {
    const d = new Date(timestamp);
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
  }

  static formatDateTime(timestamp: number): string {
    const d = new Date(timestamp);
    const h = String(d.getHours()).padStart(2, '0');
    const mi = String(d.getMinutes()).padStart(2, '0');
    return `${DateUtil.formatDate(timestamp)} ${h}:${mi}`;
  }

  /** 相对时间：刚刚/x分钟前/x小时前/x天前 */
  static relative(timestamp: number): string {
    const now = Date.now();
    const diff = now - timestamp;
    if (diff < 60 * 1000) return '刚刚';
    if (diff < 60 * 60 * 1000) return `${Math.floor(diff / 60000)}分钟前`;
    if (diff < 24 * 60 * 60 * 1000) return `${Math.floor(diff / 3600000)}小时前`;
    if (diff < 7 * 24 * 60 * 60 * 1000) return `${Math.floor(diff / 86400000)}天前`;
    return DateUtil.formatDate(timestamp);
  }

  /** 公元前/公元纪年格式化 */
  static formatYear(year: number): string {
    if (year < 0) return `公元前${-year}年`;
    if (year < 1000) return `公元${year}年`;
    return `${year}年`;
  }

  static now(): number {
    return Date.now();
  }

  /** 相对时间格式化，如"3分钟前""2小时前""昨天""3天前" */
  static formatRelative(timestamp: number): string {
    if (!timestamp || timestamp <= 0) return '';
    const diff = Date.now() - timestamp;
    const min = 60 * 1000;
    const hour = 60 * min;
    const day = 24 * hour;
    if (diff < min) return '刚刚';
    if (diff < hour) return `${Math.floor(diff / min)}分钟前`;
    if (diff < day) return `${Math.floor(diff / hour)}小时前`;
    if (diff < 2 * day) return '昨天';
    if (diff < 7 * day) return `${Math.floor(diff / day)}天前`;
    if (diff < 30 * day) return `${Math.floor(diff / (7 * day))}周前`;
    return DateUtil.formatDate(timestamp);
  }

  static uuid(): string {
    // 简易UUID（不依赖crypto）
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
      const r = Math.random() * 16 | 0;
      const v = c === 'x' ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    });
  }

  /** 返回该时间戳所在日的0点时间戳（本地时间） */
  static startOfDay(ts: number): number {
    const d = new Date(ts);
    d.setHours(0, 0, 0, 0);
    return d.getTime();
  }
}
