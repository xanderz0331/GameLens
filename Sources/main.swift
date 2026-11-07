import AppKit

// NSApplication.delegate 是弱引用，这里用全局变量把它留住。
var retainedDelegate: AnyObject?

let commandLineHandled = CLI.handleIfNeeded(CommandLine.arguments)
NSLog("[GameLens] 启动标记 v2")

// 顶层代码本来就跑在主线程，这里显式声明给编译器看。
MainActor.assumeIsolated {
    if commandLineHandled {
        RunLoop.main.run()
        return
    }

    let application = NSApplication.shared
    let delegate = AppDelegate()
    retainedDelegate = delegate
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
