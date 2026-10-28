import { LibraryPanel } from '../ui/LibraryPanel';
@Entry
@Component
struct LibraryPage {
  build() { Column() { LibraryPanel({ onBrowse: () => this.getUIContext().getRouter().pushUrl({ url: 'pages/SearchPage' }) }) }.width('100%').height('100%') }
}

