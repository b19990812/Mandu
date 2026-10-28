import { common } from '@kit.AbilityKit';
import { ReaderDatabase } from '../storage/ReaderDatabase';
import { TrackingService } from '../tracking/TrackingService';
import { viewError } from './ViewOperation';
@Observed
export class TrackingVM {
  token: string = ''; account: string = ''; subjectId: string = ''; subjectName: string = '';
  chapters: string = '0'; collection: number = 3; score: number = 0; pending: number = 0;
  status: string = '使用 Bangumi 个人访问令牌授权；令牌仅存入系统安全存储。'; busy: boolean = false;
  mangaId: string = ''; private verified: string = ''; private service?: TrackingService;
  initialize(context: common.UIAbilityContext,manga: string): void { this.mangaId = manga; this.service = new TrackingService(ReaderDatabase.shared(context)); this.run(async () => { await this.reload(); if (manga) { this.subjectId = await this.service!.binding(manga); } }); }
  private async reload(): Promise<void> { if (this.service) { const account = await this.service.account(); this.account = account.name; this.pending = await this.service.pending(); } }
  private async run(action: () => Promise<void>): Promise<void> { if (this.busy || !this.service) { return; } this.busy = true; try { await action(); await this.reload(); } catch (error) { this.status = viewError(error as Error); } finally { this.busy = false; } }
  login(): void { this.run(async () => { const token = this.token; this.token = ''; await this.service!.login(token); this.status = '账号已验证，授权已保存'; }); }
  logout(): void { this.run(async () => { await this.service!.logout(); this.status = '已移除授权；待同步记录保留，仅原账号重新授权后可发送'; }); }
  changeSubject(value: string): void { this.subjectId = value; this.verified = ''; this.subjectName = ''; }
  inspect(): void { this.run(async () => { this.subjectName = await this.service!.subject(this.subjectId); this.verified = this.subjectId; this.status = '核对条目名称与章节数后，确认加入同步队列'; }); }
  queue(): void { this.run(async () => { if (!this.verified || this.verified !== this.subjectId) { this.status = '请先校验目标条目'; return; } await this.service!.queue(this.mangaId,this.verified,Number(this.chapters),this.collection,this.score); this.status = '已加入持久同步队列；发送的是你确认的章节数，不自动推断跨站章节编号'; }); }
  sync(): void { this.run(async () => { const count = await this.service!.flush(); this.status = '本轮已同步 ' + count.toString() + ' 项'; }); }
}
