/// 記錄一次比對實際做了多少工作，讓測試用確定的數字檢查效能保護有沒有生效，而不是量時間。
final class DiffWork {
    /// 送進行層級 diff 的行數（兩側合計）
    var linesDiffed = 0
    /// 配對與搬移偵測做了幾次相似度計算
    var similarityChecks = 0
    /// 逐 token 比對了幾對行
    var inlineDiffs = 0
    /// 超過 token 上限、改成整行標示的行對數
    var inlineFallbacks = 0
    /// 搬移偵測因為超過上限而略過
    var moveDetectionSkipped = false
}
