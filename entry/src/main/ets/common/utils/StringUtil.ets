/**
 * 字符串/文本工具
 */
export class StringUtil {
  static isEmpty(s?: string | null): boolean {
    return s === null || s === undefined || s.trim().length === 0;
  }

  static notEmpty(s?: string | null): boolean {
    return !StringUtil.isEmpty(s);
  }

  /** 截断 */
  static truncate(s: string, maxLen: number, suffix = '…'): string {
    if (s.length <= maxLen) return s;
    return s.slice(0, maxLen) + suffix;
  }

  /** 简易中文/英文/数字/混排文本截断（粗略按字符宽度） */
  static truncateByWidth(s: string, maxWidth: number): string {
    let width = 0;
    let out = '';
    for (const ch of s) {
      // 中文/全角按2宽
      const w = /[\u4e00-\u9fa5\uff00-\uffef]/.test(ch) ? 2 : 1;
      if (width + w > maxWidth) return out + '…';
      out += ch;
      width += w;
    }
    return out;
  }

  /** 将 tags JSON 字符串解析为数组（容错） */
  static parseTagsArray(tags?: string): string[] {
    if (!tags) return [];
    try {
      const arr = JSON.parse(tags) as string[];
      return Array.isArray(arr) ? arr.filter((x: string) => typeof x === 'string') : [];
    } catch (e) {
      return [];
    }
  }

  /** 将数组序列化为 tags JSON */
  static toTagsArray(tags: string[]): string {
    return JSON.stringify(tags || []);
  }
}
