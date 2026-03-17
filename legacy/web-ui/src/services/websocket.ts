import type { AnalyzeResult } from '../types/api.js';

export type ResultHandler = (result: AnalyzeResult) => void;
export type StatusHandler = (connected: boolean) => void;

const RECONNECT_BASE_MS = 1000;
const RECONNECT_MAX_MS = 30000;
const RECONNECT_FACTOR = 2;

export class ResultsSocket {
  private ws: WebSocket | null = null;
  private url: string;
  private onResult: ResultHandler;
  private onStatus: StatusHandler;
  private reconnectMs = RECONNECT_BASE_MS;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private closed = false;

  constructor(onResult: ResultHandler, onStatus: StatusHandler) {
    const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
    this.url = `${proto}//${location.host}/ws/results`;
    this.onResult = onResult;
    this.onStatus = onStatus;
  }

  connect(): void {
    this.closed = false;
    this.tryConnect();
  }

  disconnect(): void {
    this.closed = true;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
  }

  private tryConnect(): void {
    if (this.closed) return;

    this.ws = new WebSocket(this.url);

    this.ws.onopen = () => {
      this.reconnectMs = RECONNECT_BASE_MS;
      this.onStatus(true);
    };

    this.ws.onmessage = (ev: MessageEvent) => {
      try {
        const result = JSON.parse(ev.data as string) as AnalyzeResult;
        this.onResult(result);
      } catch {
        // Ignore malformed messages
      }
    };

    this.ws.onclose = () => {
      this.onStatus(false);
      this.scheduleReconnect();
    };

    this.ws.onerror = () => {
      // onclose will fire after onerror, reconnect handled there
    };
  }

  private scheduleReconnect(): void {
    if (this.closed) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.tryConnect();
    }, this.reconnectMs);
    this.reconnectMs = Math.min(this.reconnectMs * RECONNECT_FACTOR, RECONNECT_MAX_MS);
  }
}
