import Foundation
import Testing
@testable import DiffEditor

@Suite struct DroppedFileTests {
    @Test func loadsUTF8Text() throws {
        let url = temporaryFile(Array("第一行\nsecond line".utf8))
        #expect(try DroppedFile.load([url]) == "第一行\nsecond line")
    }

    @Test func stripsByteOrderMark() throws {
        let url = temporaryFile([0xEF, 0xBB, 0xBF] + Array("abc".utf8))
        #expect(try DroppedFile.load([url]) == "abc")
    }

    @Test func rejectsFilesOverLimitWithoutReadingThem() throws {
        let url = temporaryFile([])
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(DroppedFile.maximumSize) + 1)
        try handle.close()
        #expect(throws: DroppedFile.LoadError.tooLarge) { try DroppedFile.load([url]) }
        #expect(DroppedFile.maximumSize == 5 * 1024 * 1024)
    }

    @Test func rejectsBinaryAndInvalidUTF8() {
        #expect(throws: DroppedFile.LoadError.notText) { try DroppedFile.load([temporaryFile([0x61, 0x00, 0x62])]) }
        #expect(throws: DroppedFile.LoadError.notText) { try DroppedFile.load([temporaryFile([0xC3, 0x28])]) }
    }

    @Test func rejectsFoldersAndMultipleFiles() {
        let folder = temporaryFile([]).deletingLastPathComponent()
        #expect(throws: DroppedFile.LoadError.notText) { try DroppedFile.load([folder]) }
        let a = temporaryFile(Array("a".utf8))
        let b = temporaryFile(Array("b".utf8))
        #expect(throws: DroppedFile.LoadError.multipleFiles) { try DroppedFile.load([a, b]) }
    }

    @Test func errorsFollowLanguage() {
        let en = Strings.for(.english)
        let zh = Strings.for(.traditionalChinese)
        #expect(DroppedFile.LoadError.tooLarge.message(en) == "The file is larger than 5 MB.")
        #expect(DroppedFile.LoadError.notText.message(zh) == "這不是 UTF-8 文字檔，無法載入。")
        #expect(DroppedFile.LoadError.multipleFiles.message(zh) == "一次只能拖放一個檔案。")
    }

    @MainActor @Test func panesAcceptDroppedFiles() {
        let f = EditorFixture()
        #expect(f.left.registeredDraggedTypes.contains(.fileURL))
        #expect(f.right.registeredDraggedTypes.contains(.fileURL))
    }

    @MainActor @Test func dropReplacesPaneAndCanBeUndone() throws {
        let f = EditorFixture()
        f.window.makeFirstResponder(f.left)
        let undo = f.left.undoManager!
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        f.load("原本的內容", "右邊")
        undo.endUndoGrouping()
        undo.beginUndoGrouping()
        try f.left.loadDroppedFiles([temporaryFile(Array("拖進來的內容".utf8))])
        undo.endUndoGrouping()
        #expect(f.left.string == "拖進來的內容")
        undo.undo()
        #expect(f.left.string == "原本的內容")
    }
}
