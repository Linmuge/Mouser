enum HIDReportNormalizer {
    static func inputBytes(reportID: UInt8?, data: [UInt8]) -> [UInt8] {
        guard let reportID, data.first != reportID else { return data }
        return [reportID] + data
    }
}
