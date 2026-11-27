import Foundation

enum WordPick {
    static func range(in text: String, unbreakable: [NSRange] = [], at offset: Int) -> NSRange? {
        let ns = text as NSString
        guard offset >= 0, offset < ns.length else { return nil }
        var picked = ns.rangeOfComposedCharacterSequence(at: offset)
        let tokenizer = CFStringTokenizerCreate(nil, text as CFString, CFRange(location: 0, length: ns.length),
                                                kCFStringTokenizerUnitWord, Locale(identifier: "ja") as CFLocale)
        if CFStringTokenizerGoToTokenAtIndex(tokenizer, offset).rawValue != 0 {
            let token = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let word = NSRange(location: token.location, length: token.length)
            if NSLocationInRange(offset, word) { picked = word }
        }
        var grew = true
        while grew {
            grew = false
            for group in unbreakable where NSIntersectionRange(group, picked).length > 0 {
                let union = NSUnionRange(group, picked)
                if union != picked {
                    picked = union
                    grew = true
                }
            }
        }
        return picked
    }
}
