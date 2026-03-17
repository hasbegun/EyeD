import type { SignalMessage } from '../types/api.js';

export type VideoTrackHandler = (stream: MediaStream) => void;
export type ConnectionStateHandler = (state: RTCPeerConnectionState) => void;

const ICE_SERVERS: RTCIceServer[] = [
  { urls: 'stun:stun.l.google.com:19302' },
];

export class DeviceStream {
  private ws: WebSocket | null = null;
  private pc: RTCPeerConnection | null = null;
  private deviceId: string;
  private onTrack: VideoTrackHandler;
  private onState: ConnectionStateHandler;
  private closed = false;

  constructor(
    deviceId: string,
    onTrack: VideoTrackHandler,
    onState: ConnectionStateHandler,
  ) {
    this.deviceId = deviceId;
    this.onTrack = onTrack;
    this.onState = onState;
  }

  connect(): void {
    this.closed = false;
    const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const url = `${proto}//${location.host}/ws/signaling?device_id=${encodeURIComponent(this.deviceId)}&role=viewer`;

    this.ws = new WebSocket(url);

    this.ws.onopen = () => {
      this.send({ type: 'join', device_id: this.deviceId, from: 'viewer' });
    };

    this.ws.onmessage = (ev: MessageEvent) => {
      try {
        const msg = JSON.parse(ev.data as string) as SignalMessage;
        this.handleSignal(msg);
      } catch {
        // Ignore malformed messages
      }
    };

    this.ws.onclose = () => {
      this.cleanup();
    };
  }

  disconnect(): void {
    this.closed = true;
    this.send({ type: 'leave', device_id: this.deviceId, from: 'viewer' });
    this.cleanup();
  }

  private cleanup(): void {
    if (this.pc) {
      this.pc.close();
      this.pc = null;
    }
    if (this.ws && this.ws.readyState <= WebSocket.OPEN) {
      this.ws.close();
    }
    this.ws = null;
  }

  private send(msg: Partial<SignalMessage>): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(msg));
    }
  }

  private async handleSignal(msg: SignalMessage): Promise<void> {
    switch (msg.type) {
      case 'offer':
        await this.handleOffer(msg.payload as unknown as RTCSessionDescriptionInit);
        break;
      case 'answer':
        if (this.pc) {
          await this.pc.setRemoteDescription(msg.payload as unknown as RTCSessionDescriptionInit);
        }
        break;
      case 'ice-candidate':
        if (this.pc && msg.payload) {
          await this.pc.addIceCandidate(msg.payload as unknown as RTCIceCandidateInit);
        }
        break;
      case 'join':
        // Device came online — it will send an offer
        break;
      case 'leave':
        // Device disconnected
        this.onState('disconnected');
        break;
    }
  }

  private async handleOffer(offer: RTCSessionDescriptionInit): Promise<void> {
    // Create new peer connection for each offer
    if (this.pc) {
      this.pc.close();
    }

    this.pc = new RTCPeerConnection({ iceServers: ICE_SERVERS });

    this.pc.ontrack = (ev) => {
      if (ev.streams[0]) {
        this.onTrack(ev.streams[0]);
      }
    };

    this.pc.onicecandidate = (ev) => {
      if (ev.candidate) {
        this.send({
          type: 'ice-candidate',
          device_id: this.deviceId,
          from: 'viewer',
          payload: ev.candidate.toJSON() as unknown,
        });
      }
    };

    this.pc.onconnectionstatechange = () => {
      if (this.pc) {
        this.onState(this.pc.connectionState);
      }
    };

    await this.pc.setRemoteDescription(offer);
    const answer = await this.pc.createAnswer();
    await this.pc.setLocalDescription(answer);

    this.send({
      type: 'answer',
      device_id: this.deviceId,
      from: 'viewer',
      payload: answer as unknown,
    });
  }
}
