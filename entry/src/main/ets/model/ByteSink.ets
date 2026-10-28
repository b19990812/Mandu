export interface ByteSink {
  write(chunk: ArrayBuffer): Promise<void>;
}
