import Foundation

/// FSRS（Free Spaced Repetition Scheduler，第 5 版）间隔复习算法，使用官方公布的默认参数。
/// 每个语法点记两样东西：
/// - 记忆稳定度 S（天）：记住率从 100% 降到 90% 需要的天数，越大越不容易忘；
/// - 难度 D（1～10）：越难的语法，每次复习后 S 涨得越慢。
/// 记住率按幂函数遗忘曲线 R(t) = (1 + F·t/S)^C 计算，降到 90% 就该复习（此时 t 恰好等于 S）。
/// 时间一律按真实经过的时间（秒→天）计算，不按日历天。
enum FSRS {
    /// 自评：忘了 / 有点模糊 / 记得（FSRS 的 Again / Hard / Good；App 不提供 Easy）
    enum Grade: Int, CaseIterable, Codable {
        case again = 1, hard = 2, good = 3
    }

    /// FSRS-5 默认参数 w0…w18
    static let w: [Double] = [0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575,
                              0.1192, 1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315, 2.9898, 0.51655, 0.6621]
    static let decay = -0.5
    static let factor = 19.0 / 81.0
    /// 目标记住率：降到这个值以下就该复习
    static let targetRetention = 0.9

    struct Memory: Codable, Hashable {
        var stability: Double
        var difficulty: Double
    }

    /// 经过 t 天后的记住率
    static func retrievability(elapsedDays t: Double, stability s: Double) -> Double {
        pow(1 + factor * max(0, t) / max(s, 0.01), decay)
    }

    /// 记住率降到 r 需要的天数（r = 0.9 时等于 S）
    static func interval(stability s: Double, retention r: Double = targetRetention) -> Double {
        s / factor * (pow(r, 1 / decay) - 1)
    }

    /// 第一次学习后的初始状态
    static func initial(_ g: Grade) -> Memory {
        Memory(stability: max(w[g.rawValue - 1], 0.1), difficulty: initialDifficulty(g.rawValue))
    }

    private static func initialDifficulty(_ g: Int) -> Double {
        clamp(w[4] - exp(w[5] * Double(g - 1)) + 1)
    }

    private static func clamp(_ d: Double) -> Double { min(10, max(1, d)) }

    /// 复习一次后的新状态。
    /// - Parameter elapsedDays: 距上一次复习过了多少天（真实时间）
    static func review(_ m: Memory, elapsedDays t: Double, grade g: Grade) -> Memory {
        let d = m.difficulty, s = m.stability
        // 难度：忘了 → 变难，记得 → 略变容易；向默认难度缓慢回归
        let delta = -w[6] * Double(g.rawValue - 3)
        let d1 = d + delta * (10 - d) / 9
        let newD = clamp(w[7] * initialDifficulty(4) + (1 - w[7]) * d1)

        let newS: Double
        if t < 1 {
            // 同一天内再次复习：只做小幅调整
            newS = s * exp(w[17] * (Double(g.rawValue) - 3 + w[18]))
        } else {
            let r = retrievability(elapsedDays: t, stability: s)
            switch g {
            case .again:
                let forget = w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp(w[14] * (1 - r))
                newS = min(forget, s)
            case .hard, .good:
                let hardPenalty = g == .hard ? w[15] : 1
                newS = s * (exp(w[8]) * (11 - d) * pow(s, -w[9]) * (exp(w[10] * (1 - r)) - 1) * hardPenalty + 1)
            }
        }
        return Memory(stability: max(newS, 0.1), difficulty: newD)
    }
}
