if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface HomePage_Params {
}
import BuildProfile from "@normalized:N&&&entry/.preview/default/generated/profile/default/BuildProfile&";
class HomePage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: HomePage_Params) {
    }
    updateStateVars(params: HomePage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
    }
    aboutToBeDeleted() {
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 24 });
            Column.debugLine("entry/src/main/ets/pages/HomePage.ets(7:5)", "entry");
            Column.justifyContent(FlexAlign.Center);
            Column.width('100%');
            Column.height('100%');
            Column.padding(28);
            Column.backgroundColor('#F7F4ED');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('漫读');
            Text.debugLine("entry/src/main/ets/pages/HomePage.ets(8:7)", "entry");
            Text.fontSize(36);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor('#254E50');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('原生鸿蒙漫画阅读');
            Text.debugLine("entry/src/main/ets/pages/HomePage.ets(9:7)", "entry");
            Text.fontSize(18);
            Text.fontColor('#485C5A');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('开发准备中');
            Text.debugLine("entry/src/main/ets/pages/HomePage.ets(10:7)", "entry");
            Text.fontSize(14);
            Text.fontColor('#697874');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('漫画源网站');
            Button.debugLine("entry/src/main/ets/pages/HomePage.ets(11:7)", "entry");
            Button.backgroundColor('#254E50');
            Button.onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/SourcesPage' }));
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (BuildProfile.DEBUG && BuildProfile.TARGET_NAME.toString() === 'lab') {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Button.createWithLabel('打开开发实验室');
                        Button.debugLine("entry/src/main/ets/pages/HomePage.ets(15:9)", "entry");
                        Button.backgroundColor('#254E50');
                        Button.onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/DebugLabPage' }));
                    }, Button);
                    Button.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
    public __resetStateVarsOnReuse__Internal(params: Object): void {
    }
    static getEntryName(): string {
        return "HomePage";
    }
}
registerNamedRoute(() => new HomePage(undefined, {}), "", { bundleName: "com.hsmihon.reader", moduleName: "entry", pagePath: "pages/HomePage", pageFullPath: "entry/src/main/ets/pages/HomePage", integratedHsp: "false", moduleType: "followWithHap" });
