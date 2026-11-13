import { hilog } from '@kit.PerformanceAnalysisKit';


// Enabled only by the lab target's explicit synthetic-reader launch parameter.
export class ReaderPerf {
  static enabled: boolean = false;
  static mode: string = 'curl';
  static lanes: number = 1;
  static automatic: boolean = true;
  static turns: number = 0;
  private static run: string = '';
  private static began: number = 0;
  private static first: boolean = false;
  private static hintText: string = '';
  private static hintAt: number = 0;
  static begin(mode: string,lanes: number,automatic: boolean = true): void {
    ReaderPerf.enabled = true; ReaderPerf.mode = mode; ReaderPerf.lanes = lanes;
    ReaderPerf.automatic = automatic;
    ReaderPerf.turns = 0; ReaderPerf.run = Date.now().toString(); ReaderPerf.began = Date.now();
    ReaderPerf.first = false; ReaderPerf.hintText = ''; ReaderPerf.hintAt = 0;
    ReaderPerf.event('run',0,'synthetic-only');
  }
  static event(stage: string,ms: number = 0,detail: string = ''): void {
    if (!ReaderPerf.enabled) { return; }
    const record: (string | number)[] = [ReaderPerf.run,ReaderPerf.mode,ReaderPerf.lanes,ReaderPerf.turns,stage,Date.now(),ms,detail];
    hilog.info(0x0001,'ReaderPerf','%{public}s',JSON.stringify(record));
  }
  static turn(index: number): void { if (!ReaderPerf.enabled) { return; } ReaderPerf.turns++; ReaderPerf.began = Date.now(); ReaderPerf.first = false; ReaderPerf.event('turn',0,index.toString()); }
  static firstFrame(sequence: number): boolean { if (ReaderPerf.enabled && !ReaderPerf.first && sequence > 0 && ReaderPerf.turns > 0) { ReaderPerf.first = true; ReaderPerf.event('first-submit',Date.now() - ReaderPerf.began); return true; } return false; }
  static firstSwapped(sequence: number): void { ReaderPerf.event('first-swap-ack',Date.now() - ReaderPerf.began,sequence.toString()); }
  static hint(value: string): void {
    if (!ReaderPerf.enabled || value === ReaderPerf.hintText) { return; }
    if (ReaderPerf.hintText) { ReaderPerf.event('hint-end',Date.now() - ReaderPerf.hintAt,ReaderPerf.hintText); }
    ReaderPerf.hintText = value; ReaderPerf.hintAt = Date.now();
    if (value) { ReaderPerf.event('hint-start',0,value); }
  }
  static committed(index: number): void { ReaderPerf.event('commit',Date.now() - ReaderPerf.began,index.toString()); }
}
