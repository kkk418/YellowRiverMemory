/**
 * 轻量级日志工具（统一tag，支持分级）
 * 发布时可通过 LOG_LEVEL 过滤。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

export class LogLevel {
  static DEBUG = 1;
  static INFO = 2;
  static WARN = 3;
  static ERROR = 4;
  static NONE = 99;
}

const LOG_DOMAIN = 0x0001;
const DEFAULT_TAG = 'YRM';
let currentLevel: number = LogLevel.DEBUG;

export class Logger {
  static setLevel(level: number): void {
    currentLevel = level;
  }

  static debug(tag: string, msg: string): void {
    if (currentLevel <= LogLevel.DEBUG) {
      hilog.debug(LOG_DOMAIN, `${DEFAULT_TAG}/${tag}`, msg);
    }
  }

  static info(tag: string, msg: string): void {
    if (currentLevel <= LogLevel.INFO) {
      hilog.info(LOG_DOMAIN, `${DEFAULT_TAG}/${tag}`, msg);
    }
  }

  static warn(tag: string, msg: string): void {
    if (currentLevel <= LogLevel.WARN) {
      hilog.warn(LOG_DOMAIN, `${DEFAULT_TAG}/${tag}`, msg);
    }
  }

  static error(tag: string, msg: string): void {
    if (currentLevel <= LogLevel.ERROR) {
      hilog.error(LOG_DOMAIN, `${DEFAULT_TAG}/${tag}`, msg);
    }
  }
}
