import SwiftUI

// @main cannot appear in main.swift (Swift language constraint: top-level executable
// code conflicts with the @main attribute). Call App.main() directly; the App protocol
// provides a default static main() implementation that bootstraps the SwiftUI runtime.
MenubarTranslateApp.main()
