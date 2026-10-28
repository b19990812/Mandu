import { CallContext, RequestPlan, Transport } from '../network/Transport';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { Database, ProbeRecord } from '../storage/Database';
import { FileStore } from '../storage/FileStore';
import { HtmlExtractor } from '../source/rules/HtmlExtractor';
import { SelectorSubset } from '../source/rules/SelectorSubset';
import { JsonExtractor } from '../source/rules/JsonExtractor';

export class FoundationLab {
  async parserProbe(): Promise<string> {
    const html = new HtmlExtractor().parse('<div id="reader"><p>中文 &amp; 实体<img data-id="p1" data-src="/1.jpg"></div>');
    const selected = new SelectorSubset().select(html, '#reader img[data-src]');
    const json = new JsonExtractor();
    const root = json.parse('{"data":{"items":[{"id":9007199254740993123}]}}');
    const id = json.at(root, '$.data.items[0].id');
    if (selected.length !== 1 || html.textContent() !== '中文 & 实体' || !id || id.scalar !== '9007199254740993123') {
      throw new AppError(ErrorCode.PARSE_ERROR, '解析器原型核验不符');
    }
    return 'HTML节点/实体与JSON大整数保真探针通过';
  }

  private readonly database: Database;
  private readonly files: FileStore;

  constructor(database: Database, files: FileStore) {
    this.database = database;
    this.files = files;
  }

  async readStorage(): Promise<string> {
    const record = await this.database.readProbe();
    const file = this.files.readText('probe_record');
    if (!record && file === undefined) { return '尚未写入。先写入一次，再关闭应用重开读取。'; }
    if (!record || file !== record.value + ':' + record.updatedAt.toString()) {
      throw new AppError(ErrorCode.CORRUPT_FILE, '数据库与文件探针不一致；保留原数据以便排查');
    }
    return '数据库与私有文件一致；写入时间：' + new Date(record.updatedAt).toLocaleString();
  }

  async writeStorage(): Promise<string> {
    const record: ProbeRecord = { value: 'hs-mihon-p0', updatedAt: Date.now() };
    await this.files.writeText('probe_record', record.value + ':' + record.updatedAt.toString());
    await this.database.writeProbe(record);
    return this.readStorage();
  }

  async request(baseUrl: string, path: string, transport: Transport, ctx: CallContext): Promise<string> {
    const response = await transport.send(this.plan(baseUrl, path), ctx);
    return 'HTTP ' + response.statusCode.toString() + '；正文 ' + response.bytes.toString() + ' 字节';
  }

  async stream(baseUrl: string, transport: Transport, ctx: CallContext): Promise<string> {
    const bytes = await this.files.writeStream('network_probe', async (sink) => {
      const response = await transport.streamToFile(this.plan(baseUrl, '/probe-file'), ctx, sink);
      if (response.statusCode !== 200) {
        throw new AppError(ErrorCode.NETWORK_ERROR, '流式探针未返回 HTTP 200');
      }
    });
    if (this.files.readText('network_probe') !== 'hs-mihon fixture stream\n') {
      throw new AppError(ErrorCode.CORRUPT_FILE, '流式文件内容与自有样本不符');
    }
    return '已流式写入并核对私有文件：' + bytes.toString() + ' 字节';
  }

  private plan(baseUrl: string, path: string): RequestPlan {
    return {
      sourceId: 'org.hsmihon.fixture', url: baseUrl + path,
      headers: [{ name: 'Accept', value: 'application/json, text/plain' }], maxBytes: 2 * 1024 * 1024
    };
  }
}
