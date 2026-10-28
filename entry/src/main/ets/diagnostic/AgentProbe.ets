import { common } from '@kit.AbilityKit';
import { request } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { CallContext } from '../model/RequestTypes';
import { FileStore } from '../storage/FileStore';
import { checkCall } from '../source/SourceHttp';
import { AppError, ErrorCode } from '../model/ErrorTypes';

interface AgentObservation { status: number; state: number; bytes: number; }

// Uses only the explicitly selected self-owned lab server. No production URLs.
export async function runAgentProbe(context: common.UIAbilityContext, base: string, ctx: CallContext): Promise<string> {
  const files = new FileStore(context.filesDir, 'agent_probe');
  const run = async (name: string, path: string, ends: number): Promise<AgentObservation> => {
    checkCall(ctx); files.remove(name); let task: request.agent.Task | undefined = undefined; let status = 0; const token = util.generateRandomUUID();
    try {
      task = await request.agent.create(context, { action: request.agent.Action.DOWNLOAD, url: base + path,
        title: 'HS Mihon bounded probe', description: 'self-owned fixture only', mode: request.agent.Mode.BACKGROUND,
        overwrite: true, saveas: files.localPath(name) + '.part', retry: false, redirect: false, network: request.agent.Network.ANY,
        metered: true, roaming: false, token: token, ends: ends, timeout: { connectionTimeout: 5, totalTimeout: 10 } });
      const current = task;
      current.on('response', (response: request.agent.HttpResponse) => { status = response.statusCode; });
      await current.start();
      let state = request.agent.State.INITIALIZED;
      const until = Math.min(ctx.deadlineMs, Date.now() + 12000);
      while (Date.now() < until) {
        checkCall(ctx); const info = await request.agent.touch(current.tid, token); state = info.progress.state;
        if ([request.agent.State.COMPLETED,request.agent.State.FAILED,request.agent.State.STOPPED].indexOf(state) >= 0) { break; }
        await new Promise<void>((resolve) => setTimeout(resolve, 150));
      }
      const local = files.localPath(name) + '.part'; const size = fs.accessSync(local) ? fs.statSync(local).size : 0;
      return { status: status, state: state, bytes: size };
    } catch (error) {
      if (error instanceof AppError) { throw error; } throw new AppError(ErrorCode.IO_ERROR, '系统下载代理探针失败');
    } finally { if (task) { try { await request.agent.remove(task.tid); } catch (_) {} } files.remove(name); }
  };
  const ordinary = await run('ordinary', '/images/page-1.png?range=off', -1);
  const capped = await run('ignored_range', '/images/page-1.png?range=off', 1023);
  const ranged = await run('range_positive', '/images/page-1.png', 33554431);
  const lying = await run('range_lie', '/fault/range-lie', 1023);
  const chunked = await run('chunked_lie', '/fault/range-chunked-lie', 1023);
  const redirect = await run('redirect', '/fault/cross-host', -1);
  return '代理探针：普通 status=' + ordinary.status.toString() + ' state=' + ordinary.state.toString() + ' bytes=' + ordinary.bytes.toString() +
    '；Range忽略 status=' + capped.status.toString() + ' state=' + capped.state.toString() + ' bytes=' + capped.bytes.toString() +
    '；Range有效 state=' + ranged.state.toString() + ' bytes=' + ranged.bytes.toString() +
    '；伪Range state=' + lying.state.toString() + ' bytes=' + lying.bytes.toString() +
    '；伪分块Range state=' + chunked.state.toString() + ' bytes=' + chunked.bytes.toString() +
    '；禁止跳转 status=' + redirect.status.toString() + ' state=' + redirect.state.toString() + ' bytes=' + redirect.bytes.toString();
}
