import { HistoryPanel } from '../ui/HistoryPanel';

@Entry
@Component
struct HistoryPage {
  @State private revision: number = 0;
  onPageShow(): void { this.revision++; }
  build() {
    Column() {
      HistoryPanel({ revision: this.revision })
    }.width('100%').height('100%')
  }
}
