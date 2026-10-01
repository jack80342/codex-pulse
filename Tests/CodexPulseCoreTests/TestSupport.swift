import Testing

func expectThrows<T>(
    _ operation: @autoclosure () throws -> T,
    _ inspect: (Error) -> Void = { _ in }
) {
    do {
        _ = try operation()
        Issue.record("预期操作抛出错误，实际成功。", sourceLocation: SourceLocation(
            fileID: #fileID, filePath: #filePath, line: #line, column: #column
        ))
    } catch { inspect(error) }
}
